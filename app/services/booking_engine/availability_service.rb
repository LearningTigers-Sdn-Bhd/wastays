module BookingEngine
  class AvailabilityService
    PricingOption = Struct.new(:rate_plan, :currency, :total_price, :nightly_price, :nightly_rates, :winning_rule, keyword_init: true)

    RULE_PRIORITY = {
      "ph" => 5, # Public Holiday
      "sh" => 4, # School Holiday
      "wk" => 3, # Weekend
      "gp" => 2, # General Pricing
      "base" => 1 # Room Base Price
    }.freeze

    attr_reader :params, :check_in, :check_out, :adults, :children, :room_count

    def initialize(params)
      @params = params
      @city = params[:city]
      @check_in = parse_date(params[:check_in]) || Date.current
      @check_out = parse_date(params[:check_out]) || Date.tomorrow
      @adults = (params[:adults] || 2).to_i
      @children = (params[:children] || 0).to_i
      @room_count = (params[:room_count] || 1).to_i
    end

    def find_available_hotels
      # 1. Base query: active hotels
      hotels = Hotel.where(status: [ "approved", "live" ])
      hotels = hotels.where("city ILIKE ?", "%#{@city}%") if @city.present?

      # 2. Filter by availability
      # Note: Initial implementation for availability checks. For higher volume properties, consider specialized indexing.
      hotels.select do |hotel|
        available_rooms_for_hotel(hotel).any?
      end
    end

    def available_rooms_for_hotel(hotel)
      # Get stay dates (excluding check-out day)
      stay_dates = (@check_in...@check_out).to_a
      return [] if stay_dates.empty?

      # 1. Basic occupancy filter
      # In V3, we assume guest specifies TOTAL adults/children for the whole booking.
      # For now, let's say ANY room type that can fit the guests is a candidate.
      potential_room_types = hotel.room_types.where("max_adults >= ?", @adults)

      # 2. Date-based availability & rate check
      available_room_types = potential_room_types.select do |room_type|
        # Check inventory for all stay dates
        inventories = room_type.room_inventories.where(date: stay_dates)

        # Must have open inventory with quantity >= required room_count for EVERY stay date
        inventory_ok = (inventories.count == stay_dates.count) &&
                       inventories.all? { |inv| inv.status == "open" && inv.quantity >= @room_count }

        next false unless inventory_ok

        pricing_options_for(room_type).any?
      end

      available_room_types
    end

    def pricing_summary_for(room_type)
      option = lowest_pricing_option_for(room_type)
      return {} if option.blank?

      display_name = option.rate_plan&.name
      if %w[wk sh ph].include?(option.winning_rule)
        display_name = human_rule_name(option.winning_rule)
      end

      {
        rate_plan: option.rate_plan,
        rate_plan_name: display_name,
        currency: option.currency,
        total_price: option.total_price,
        nightly_price: option.nightly_price,
        nightly_rates: option.nightly_rates,
        available_rate_plans: pricing_options_for(room_type).map(&:rate_plan).compact
      }
    end

    def calculate_total_price(room_type, rate_plan: nil)
      option = rate_plan.present? ? pricing_option_for(room_type, rate_plan) : lowest_pricing_option_for(room_type)
      option&.total_price || 0.to_d
    end

    private

    def human_rule_name(rule_type)
      case rule_type
      when "ph" then "Public Holiday Rate"
      when "sh" then "School Holiday Rate"
      when "wk" then "Weekend Rate"
      else nil
      end
    end

    def parse_date(date_param)
      return date_param if date_param.is_a?(Date)
      return nil if date_param.blank?

      begin
        Date.parse(date_param)
      rescue ArgumentError
        nil
      end
    end

    def stay_dates
      @stay_dates ||= (@check_in...@check_out).to_a
    end

    def nights
      stay_dates.length
    end

    def pricing_options_for(room_type)
      candidate_rate_plans_for(room_type).filter_map do |rate_plan|
        pricing_option_for(room_type, rate_plan)
      end
    end

    def lowest_pricing_option_for(room_type)
      # Prioritize by rule priority (e.g. PH > SH > WK > GP > Base)
      # Then by total price (cheapest first)
      pricing_options_for(room_type).sort_by { |opt|
        [ -RULE_PRIORITY.fetch(opt.winning_rule, 0), opt.total_price ]
      }.first
    end

    def candidate_rate_plans_for(room_type)
      [ nil ] + room_type.rate_plans.order(:id).to_a
    end

    def pricing_option_for(room_type, rate_plan)
      currency = rate_plan&.currency.presence || room_type.hotel.default_currency.presence || "MYR"
      scope = room_type.room_rates.where(date: stay_dates, currency: currency)
      scope = rate_plan.present? ? scope.where(rate_plan: rate_plan) : scope.where(rate_plan_id: nil)
      rates_by_date = scope.index_by(&:date)

      nightly_total = 0.to_d
      winning_rule = "base"
      highest_priority = 0

      stay_dates.each do |date|
        rate = rates_by_date[date]
        price = nightly_price_for(date, rate, room_type)
        return nil if price.nil? # Stay is restricted or unpriced on this date

        nightly_total += price

        rule_type = rate&.applied_rule_type || "base"
        priority = RULE_PRIORITY[rule_type] || 0
        if priority > highest_priority
          highest_priority = priority
          winning_rule = rule_type
        end
      end

      PricingOption.new(
        rate_plan: rate_plan,
        currency: currency,
        total_price: nightly_total * @room_count,
        nightly_price: nightly_total / nights,
        nightly_rates: rates_by_date,
        winning_rule: winning_rule
      )
    end

    def nightly_price_for(date, rate, room_type)
      if rate.present?
        # 1. Check Restrictions
        return nil if rate.stop_sell?
        return nil if date == stay_dates.first && rate.closed_to_arrival?
        return nil if date == stay_dates.last && rate.closed_to_departure?
        return nil if rate.min_stay.present? && nights < rate.min_stay
        return nil if rate.max_stay.present? && nights > rate.max_stay

        # 2. Resolve Price
        rate.price
      else
        # 3. Fallback to base price if no specific rate record exists
        room_type.base_price.presence
      end
    end
  end
end
