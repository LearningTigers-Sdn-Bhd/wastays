module BookingEngine
  class AvailabilityService
    PricingOption = Struct.new(:rate_plan, :currency, :total_price, :nightly_price, :nightly_rates, keyword_init: true)

    attr_reader :params, :check_in, :check_out, :adults, :children, :room_count, :partner_code

    def initialize(params)
      @params = params
      @city = params[:city]
      @check_in = parse_date(params[:check_in]) || Date.current
      @check_out = parse_date(params[:check_out]) || Date.tomorrow
      @adults = (params[:adults] || 2).to_i
      @children = (params[:children] || 0).to_i
      @room_count = (params[:room_count] || 1).to_i
      @partner_code = params[:partner_code].to_s.strip.upcase.presence
    end

    def find_available_hotels
      # 1. Base query: active hotels
      hotels = Hotel.where(status: [ "approved", "live" ])
      hotels = hotels.where("city ILIKE ?", "%#{@city}%") if @city.present?

      # 2. Filter by availability
      # Note: This is simplified for MVP. For production with many hotels, use specialized indexing.
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

      partner = find_partner_for(room_type.hotel)

      {
        rate_plan: option.rate_plan,
        rate_plan_name: option.rate_plan&.name,
        currency: option.currency,
        total_price: option.total_price,
        nightly_price: option.nightly_price,
        nightly_rates: option.nightly_rates,
        available_rate_plans: pricing_options_for(room_type).map(&:rate_plan).compact,
        partner: partner
      }
    end

    def calculate_total_price(room_type, rate_plan: nil)
      option = rate_plan.present? ? pricing_option_for(room_type, rate_plan) : lowest_pricing_option_for(room_type)
      option&.total_price || 0.to_d
    end

    private

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
      pricing_options_for(room_type).min_by(&:total_price)
    end

    def candidate_rate_plans_for(room_type)
      plans = room_type.rate_plans.order(:id).to_a
      plans.presence || [ nil ]
    end

    def pricing_option_for(room_type, rate_plan)
      currency = rate_plan&.currency.presence || room_type.hotel.default_currency.presence || "MYR"
      scope = room_type.room_rates.where(date: stay_dates, currency: currency)
      scope = rate_plan.present? ? scope.where(rate_plan: rate_plan) : scope.where(rate_plan_id: nil)
      rates_by_date = scope.index_by(&:date)
      return nil unless rates_by_date.size == stay_dates.size

      partner = find_partner_for(room_type.hotel)

      first_rate = rates_by_date[stay_dates.first]
      last_rate = rates_by_date[stay_dates.last]
      return nil if rates_by_date.values.any?(&:stop_sell?)
      return nil if first_rate&.closed_to_arrival?
      return nil if last_rate&.closed_to_departure?
      return nil if rates_by_date.values.any? { |rate| rate.min_stay.present? && nights < rate.min_stay }
      return nil if rates_by_date.values.any? { |rate| rate.max_stay.present? && nights > rate.max_stay }

      nightly_total = rates_by_date.values.sum do |rate|
        price = if partner.present?
          rate.corporate_price.presence || rate.price
        else
          rate.price
        end
        price.to_d
      end

      PricingOption.new(
        rate_plan: rate_plan,
        currency: currency,
        total_price: nightly_total * @room_count,
        nightly_price: nightly_total / nights,
        nightly_rates: rates_by_date
      )
    end

    def find_partner_for(hotel)
      return nil if @partner_code.blank?
      return @matched_partner if defined?(@matched_partner) && @matched_partner&.hotel_id == hotel.id

      @matched_partner = hotel.partners.find_by(code: @partner_code)
    end
  end
end
