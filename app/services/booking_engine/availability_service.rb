# frozen_string_literal: true

module BookingEngine
  class AvailabilityService
    PricingOption = Struct.new(:rate_plan, :currency, :total_price, :nightly_price, :nightly_rates, :winning_rule, keyword_init: true)
    AllocationOption = Struct.new(:rooms, :total_pax, :total_price, :currency, keyword_init: true)
    AllocatedRoom = Struct.new(:room_type, :quantity, :pax, :adults, :children, :child_ages, :price_per_room, :pricing_summary, keyword_init: true)

    RULE_PRIORITY = {
      "ph" => 5, # Public Holiday
      "sh" => 4, # School Holiday
      "wk" => 3, # Weekend
      "gp" => 2, # General Pricing
      "base" => 1 # Room Base Price
    }.freeze

    attr_reader :params, :check_in, :check_out, :adults, :children, :room_count, :child_ages

    def initialize(params)
      @params = params
      @city = params[:city]
      @check_in = parse_date(params[:check_in]) || Date.current
      @check_out = parse_date(params[:check_out]) || Date.tomorrow
      @adults = (params[:adults] || 2).to_i
      @children = (params[:children] || 0).to_i
      @room_count = (params[:room_count] || 1).to_i
      @corporate_rate = [ true, "true", 1, "1" ].include?(params[:corporate_rate])
      @child_ages = normalize_child_ages(params[:child_ages], @children)
    end

    def find_available_hotels
      # 1. Base query: active hotels
      hotels = Hotel.where(status: [ "approved", "live" ])
      hotels = hotels.where("city ILIKE ?", "%#{@city}%") if @city.present?

      # 2. Filter by availability using find_each to avoid memory bloat
      available_hotels = []
      hotels.find_each do |hotel|
        available_hotels << hotel if available_rooms_for_hotel(hotel).any?
      end
      available_hotels
    end

    def available_rooms_for_hotel(hotel, allow_restricted: false)
      # Get stay dates (excluding check-out day)
      stay_dates_list = stay_dates
      return [] if stay_dates_list.empty?

      # 1. Basic occupancy filter and preload associations for performance
      potential_room_types = hotel.room_types.where("max_adults >= ?", @adults).to_a
      preload_availability_data(potential_room_types)

      # 2. Date-based availability & rate check
      available_room_types = potential_room_types.select do |room_type|
        # Check inventory for all stay dates in memory to avoid N+1
        inventories = room_type.room_inventories.select { |inv| stay_dates_list.include?(inv.date) }

        # Must have open inventory with quantity >= required room_count for EVERY stay date
        inventory_ok = (inventories.count == stay_dates_list.count) &&
                       inventories.all? { |inv| inv.status == "open" && inv.quantity >= @room_count }

        next false unless inventory_ok

        pricing_options_for(room_type).any? || (allow_restricted && stay_restriction_error_message(room_type).present?)
      end

      available_room_types
    end

    def stay_restriction_error_message(room_type)
      # If there is at least one valid pricing option, there is no blocking restriction.
      return nil if pricing_options_for(room_type).any?

      # Otherwise, let's find if any rates have stay restrictions that were violated.
      stay_dates_list = stay_dates
      return nil if stay_dates_list.empty?

      messages = []

      candidate_rate_plans_for(room_type).each do |rate_plan|
        currency = rate_plan&.currency.presence || room_type.hotel.default_currency.presence || "MYR"

        # Check check-out date for CTD restriction
        checkout_rate = room_type.room_rates.find do |rr|
          rr.date == @check_out &&
            rr.currency == currency &&
            (rate_plan.present? ? rr.rate_plan_id == rate_plan.id : rr.rate_plan_id.nil?)
        end

        if (checkout_rate.nil? || checkout_rate.rate_plan_id.nil?) && room_type.rate_plans.present?
          standard_plan = room_type.standard_rate_plan
          std_checkout_rate = room_type.room_rates.find do |rr|
            rr.date == @check_out &&
              rr.currency == currency &&
              rr.rate_plan_id == standard_plan.id
          end
          checkout_rate = std_checkout_rate if std_checkout_rate
        end

        if checkout_rate&.closed_to_departure?
          messages << "Check-out is not allowed on this date (Closed to Departure)."
        end

        rates_by_date = room_type.room_rates.select do |rr|
          stay_dates_list.include?(rr.date) &&
            rr.currency == currency &&
            (rate_plan.present? ? rr.rate_plan_id == rate_plan.id : rr.rate_plan_id.nil?)
        end.index_by(&:date)

        stay_dates_list.each do |date|
          rate = rates_by_date[date]

          if rate.nil? || rate.rate_plan_id.nil?
            std_rate = standard_rate_for(date, room_type)
            if std_rate.present?
              if date == @check_in && std_rate.closed_to_arrival?
                messages << "Check-in is not allowed on this date (Closed to Arrival)."
              end
              if date == stay_dates_list.last && std_rate.closed_to_departure?
                messages << "Check-out is not allowed on this date (Closed to Departure)."
              end
              if std_rate.min_stay.present? && nights < std_rate.min_stay
                messages << "Minimum stay is #{std_rate.min_stay} night(s) for this room."
              end
              if std_rate.max_stay.present? && nights > std_rate.max_stay
                messages << "Maximum stay is #{std_rate.max_stay} night(s) for this room."
              end
            end
          end

          if rate.present?
            if date == @check_in && rate.closed_to_arrival?
              messages << "Check-in is not allowed on this date (Closed to Arrival)."
            end
            if date == stay_dates_list.last && rate.closed_to_departure?
              messages << "Check-out is not allowed on this date (Closed to Departure)."
            end
            if rate.min_stay.present? && nights < rate.min_stay
              messages << "Minimum stay is #{rate.min_stay} night(s) for this rate."
            end
            if rate.max_stay.present? && nights > rate.max_stay
              messages << "Maximum stay is #{rate.max_stay} night(s) for this rate."
            end
          end
        end
      end

      # Return the first restriction message we found
      first_message = messages.uniq.first
      "#{first_message} Please select another date." if first_message.present?
    end

    def allocation_options_for_hotel(hotel)
      total_pax = @adults + @children
      stay_dates_list = stay_dates
      return [] if stay_dates_list.empty?

      # 1. Get all potential room types with their availability
      potential_room_types = hotel.room_types.to_a
      preload_availability_data(potential_room_types)

      room_type_data = potential_room_types.map do |room_type|
        # Check inventory
        inventories = room_type.room_inventories.select { |inv| stay_dates_list.include?(inv.date) }
        available_qty = (inventories.count == stay_dates_list.count) ? inventories.map(&:quantity).min : 0
        available_qty = 0 if inventories.any? { |inv| inv.status != "open" }

        next nil if available_qty <= 0

        {
          room_type: room_type,
          max_capacity: room_type.max_capacity,
          available_qty: available_qty
        }
      end.compact

      return [] if room_type_data.empty?

      options = []

      # 2. Single-Type Allocations
      room_type_data.each do |data|
        next if data[:max_capacity] <= 0
        req_rooms = min_rooms_for(data[:room_type], @adults, @children)
        next if req_rooms.nil?
        # Support flexibility: use room_count if the user requested more rooms (e.g. 1,1,1)
        req_rooms = [ req_rooms, @room_count ].max

        if req_rooms <= data[:available_qty]
          occupancies = distribute_guests(@adults, @children, Array.new(req_rooms) { data[:room_type] }, child_ages: @child_ages)

          if occupancies.present?
            grouped = occupancies.group_by { |occ| [ occ[:adults], occ[:children], occ[:child_ages].to_a.sort ] }

            allocated_rooms = []
            total_price = 0.to_d
            currency = nil

            grouped.each do |(r_adults, r_children, r_child_ages), list|
              quantity = list.size
              pricing = lowest_pricing_option_for(data[:room_type], adults: r_adults, children: r_children, room_count: 1, child_ages: r_child_ages)
              next if pricing.blank?

              currency ||= pricing.currency
              total_price += pricing.total_price * quantity

              allocated_rooms << AllocatedRoom.new(
                room_type: data[:room_type],
                quantity: quantity,
                pax: r_adults + r_children,
                adults: r_adults,
                children: r_children,
                child_ages: r_child_ages,
                price_per_room: pricing.total_price,
                pricing_summary: pricing_summary_for(data[:room_type], adults: r_adults, children: r_children, room_count: 1, child_ages: r_child_ages)
              )
            end

            if allocated_rooms.any?
              options << AllocationOption.new(
                rooms: allocated_rooms,
                total_pax: total_pax,
                total_price: total_price,
                currency: currency
              )
            end
          end
        end
      end

      # 3. Simple Greedy Mixed-Type Allocation
      sorted_data = room_type_data.map do |d|
        pricing = lowest_pricing_option_for(d[:room_type], adults: d[:max_capacity], children: 0, room_count: 1)
        next nil if pricing.blank?
        d.merge(pricing: pricing)
      end.compact.sort_by { |d| [ -d[:max_capacity], d[:pricing].total_price ] }

      greedy_option = greedy_allocate(total_pax, sorted_data)
      options << greedy_option if greedy_option

      options.uniq { |opt| opt.rooms.map { |r| [ r.room_type.id, r.quantity, r.adults, r.children, r.child_ages.to_a.sort ] }.sort }.sort_by(&:total_price)
    end

    def pricing_summary_for(room_type, rate_plan: nil, pax: nil, adults: nil, children: nil, room_count: nil, child_ages: [])
      option = rate_plan.present? ? pricing_option_for(room_type, rate_plan, pax: pax, adults: adults, children: children, room_count: room_count, child_ages: child_ages) : lowest_pricing_option_for(room_type, pax: pax, adults: adults, children: children, room_count: room_count, child_ages: child_ages)
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
        available_rate_plans: pricing_options_for(room_type, pax: pax, adults: adults, children: children, room_count: room_count, child_ages: child_ages).map(&:rate_plan).compact
      }
    end

    def calculate_total_price(room_type, rate_plan: nil, pax: nil, adults: nil, children: nil, room_count: nil, child_ages: [])
      option = rate_plan.present? ? pricing_option_for(room_type, rate_plan, pax: pax, adults: adults, children: children, room_count: room_count, child_ages: child_ages) : lowest_pricing_option_for(room_type, pax: pax, adults: adults, children: children, room_count: room_count, child_ages: child_ages)
      option&.total_price || 0.to_d
    end

    private

    def per_child_price(price, rate_plan, age)
      band = rate_plan.age_banded? ? rate_plan.band_for_age(age) : nil
      return band.price_for(price) if band

      price * (rate_plan.child_price_multiplier || 1.to_d)
    end

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

    # If the supplied ages don't match the children count, ignore them entirely
    # and let pricing fall back to the rate plan's flat child_price_multiplier.
    # A client-side mismatch should never break availability search.
    def normalize_child_ages(raw_ages, children_count)
      ages = Array(raw_ages).map(&:to_i)
      return [] if ages.size != children_count
      ages
    end

    # Preloads only the room_inventories/room_rates rows relevant to this
    # search's date range, instead of every historical row for the room
    # type. Unscoped `includes` here previously loaded a room type's full
    # rate/inventory history on every search request.
    def preload_availability_data(room_types)
      return if room_types.empty?

      ActiveRecord::Associations::Preloader.new(
        records: room_types,
        associations: :room_inventories,
        scope: RoomInventory.where(date: stay_dates)
      ).call

      # Inclusive of @check_out: CTD (closed-to-departure) restrictions are
      # keyed off the checkout date's own rate record, which falls outside
      # the exclusive stay_dates range.
      ActiveRecord::Associations::Preloader.new(
        records: room_types,
        associations: :room_rates,
        scope: RoomRate.where(date: @check_in..@check_out)
      ).call

      ActiveRecord::Associations::Preloader.new(
        records: room_types,
        associations: :rate_plans
      ).call

      ActiveRecord::Associations::Preloader.new(
        records: room_types,
        associations: :room_type_rate_plans
      ).call
    end

    def nights
      stay_dates.length
    end

    # Minimum number of rooms of this type needed to fit the party, respecting
    # not just total capacity but also the room's separate adult/children caps
    # (e.g. a room with max_capacity 3 but max_adults 2 can't seat 3 adults alone).
    # Returns nil if this room type can never fit the given adults/children combo.
    def min_rooms_for(room_type, adults, children)
      by_capacity = (adults + children).to_f / room_type.max_capacity

      max_adults = room_type.max_adults.to_i
      return nil if adults.positive? && max_adults <= 0
      by_adults = adults.positive? ? adults.to_f / max_adults : 0

      max_children = room_type.max_children.to_i
      return nil if children.positive? && max_children <= 0
      by_children = children.positive? ? children.to_f / max_children : 0

      [ by_capacity, by_adults, by_children ].max.ceil
    end

    def distribute_guests(adults, children, rooms, child_ages: [])
      num_rooms = rooms.size
      return nil if adults < num_rooms # Every room must have at least 1 adult

      ages_pool = (child_ages.size == children) ? child_ages.dup : []

      occupancies = Array.new(num_rooms) do |i|
        { room_type: rooms[i], adults: 0, children: 0, child_ages: [] }
      end

      # 1. Distribute 1 adult per room first
      temp_adults = adults
      num_rooms.times do |i|
        occupancies[i][:adults] = 1
        temp_adults -= 1
      end

      # 2. Guest pool
      guest_pool = [
        { key: :adults, count: temp_adults },
        { key: :children, count: children }
      ]

      guest_pool.each do |pool|
        temp_count = pool[:count]
        next if temp_count <= 0

        num_rooms.times do |i|
          room_type = occupancies[i][:room_type]
          current_total = occupancies[i][:adults] + occupancies[i][:children]
          space_left = room_type.max_capacity - current_total

          # Enforce specific guest type limit for adults or children
          if pool[:key] == :adults
            specific_limit = room_type.max_adults.to_i
            current_specific = occupancies[i][:adults]
          else
            specific_limit = room_type.max_children.to_i
            current_specific = occupancies[i][:children]
          end

          specific_space = [ specific_limit - current_specific, 0 ].max
          space_left = [ space_left, specific_space ].min
          next if space_left <= 0

          to_add = [ space_left, temp_count ].min
          occupancies[i][pool[:key]] += to_add
          if pool[:key] == :children && ages_pool.any?
            occupancies[i][:child_ages].concat(ages_pool.shift(to_add))
          end
          temp_count -= to_add
          break if temp_count <= 0
        end

        return nil if temp_count > 0
      end

      occupancies
    end

    def pricing_options_for(room_type, pax: nil, adults: nil, children: nil, room_count: nil, child_ages: [])
      candidate_rate_plans_for(room_type).filter_map do |rate_plan|
        pricing_option_for(room_type, rate_plan, pax: pax, adults: adults, children: children, room_count: room_count, child_ages: child_ages)
      end
    end

    def lowest_pricing_option_for(room_type, pax: nil, adults: nil, children: nil, room_count: nil, child_ages: [])
      pricing_options_for(room_type, pax: pax, adults: adults, children: children, room_count: room_count, child_ages: child_ages).sort_by { |opt|
        [ -RULE_PRIORITY.fetch(opt.winning_rule, 0), opt.total_price ]
      }.first
    end

    def candidate_rate_plans_for(room_type)
      plans = room_type.rate_plans.publicly_bookable.to_a

      # A per-room property also offers the unplanned "base" option (nil),
      # priced straight off the room type. A per-guest property has no
      # per-room number to fall back to, so every option carries a plan.
      room_type.hotel.sells_per_person? ? plans : [ nil ] + plans
    end

    def greedy_allocate(total_pax, room_type_data)
      return nil if room_type_data.blank?
      remaining_pax = total_pax
      allocated_rooms = []
      total_price = 0.to_d
      currency = room_type_data.first[:pricing].currency

      # Deep copy availability to track within greedy loop
      availability = room_type_data.each_with_object({}) { |d, h| h[d[:room_type].id] = d[:available_qty] }

      selected_rooms = []

      while remaining_pax > 0
        best_fit = room_type_data.select { |d| availability[d[:room_type].id] > 0 && d[:max_capacity] > 0 }
                                 .sort_by { |d| [ -[ d[:max_capacity], remaining_pax ].min, d[:pricing]&.total_price || 999999 ] }
                                 .first
        break unless best_fit

        availability[best_fit[:room_type].id] -= 1
        remaining_pax -= best_fit[:max_capacity]
        selected_rooms << best_fit[:room_type]
      end

      return nil if remaining_pax > 0 || selected_rooms.empty?

      occupancies = nil
      attempts = 0
      while occupancies.nil? && attempts <= selected_rooms.size + 3
        occupancies = distribute_guests(@adults, @children, selected_rooms.sort_by { |rt| -rt.max_capacity }, child_ages: @child_ages)
        break if occupancies.present?

        # Raw capacity was enough but a per-room sub-cap (e.g. max_adults) wasn't
        # — add another room of the cheapest available type and retry.
        extra = room_type_data.select { |d| availability[d[:room_type].id] > 0 }
                               .min_by { |d| d[:pricing]&.total_price || Float::INFINITY }
        break unless extra

        availability[extra[:room_type].id] -= 1
        selected_rooms << extra[:room_type]
        attempts += 1
      end

      return nil if occupancies.nil?

      grouped = occupancies.group_by { |occ| [ occ[:room_type], occ[:adults], occ[:children], occ[:child_ages].to_a.sort ] }

      allocated_items = []
      grouped.each do |(room_type, r_adults, r_children, r_child_ages), list|
        quantity = list.size
        pricing = lowest_pricing_option_for(room_type, adults: r_adults, children: r_children, room_count: 1, child_ages: r_child_ages)
        next if pricing.blank?

        total_price += pricing.total_price * quantity
        allocated_items << AllocatedRoom.new(
          room_type: room_type,
          quantity: quantity,
          pax: r_adults + r_children,
          adults: r_adults,
          children: r_children,
          child_ages: r_child_ages,
          price_per_room: pricing.total_price,
          pricing_summary: pricing_summary_for(room_type, adults: r_adults, children: r_children, room_count: 1, child_ages: r_child_ages)
        )
      end

      AllocationOption.new(
        rooms: allocated_items,
        total_pax: total_pax,
        total_price: total_price,
        currency: currency
      )
    end

    def pricing_option_for(room_type, rate_plan, pax: nil, adults: nil, children: nil, room_count: nil, child_ages: [])
      r_adults = (adults || pax || (@adults + @children)).to_i
      r_children = (children || 0).to_i
      r_pax = r_adults + r_children
      r_child_ages = Array(child_ages).map(&:to_i)

      room_count ||= @room_count
      currency = rate_plan&.currency.presence || room_type.hotel.default_currency.presence || "MYR"

      # Check check-out date for CTD restriction
      checkout_rate = room_type.room_rates.find do |rr|
        rr.date == @check_out &&
          rr.currency == currency &&
          (rate_plan.present? ? rr.rate_plan_id == rate_plan.id : rr.rate_plan_id.nil?)
      end

      # Fallback to standard rate plan if checking base plan (nil)
      if (checkout_rate.nil? || checkout_rate.rate_plan_id.nil?) && room_type.rate_plans.present?
        standard_plan = room_type.standard_rate_plan
        std_checkout_rate = room_type.room_rates.find do |rr|
          rr.date == @check_out &&
            rr.currency == currency &&
            rr.rate_plan_id == standard_plan.id
        end
        checkout_rate = std_checkout_rate if std_checkout_rate
      end

      return nil if checkout_rate&.closed_to_departure?

      # Filter rates in memory to avoid N+1
      rates_by_date = room_type.room_rates.select do |rr|
        stay_dates.include?(rr.date) &&
          rr.currency == currency &&
          (rate_plan.present? ? rr.rate_plan_id == rate_plan.id : rr.rate_plan_id.nil?)
      end.index_by(&:date)

      nightly_total = 0.to_d
      winning_rule = "base"
      highest_priority = 0
      complete_rates_by_date = {}

      stay_dates.each do |date|
        rate = rates_by_date[date]
        price = nightly_price_for(date, rate, room_type, rate_plan)
        return nil if price.nil? # Stay is restricted or unpriced on this date

        if rate_plan&.sell_mode == "per_person"
          adults_cost = r_adults * price
          children_cost =
            if r_child_ages.size == r_children && r_child_ages.any?
              r_child_ages.sum { |age| per_child_price(price, rate_plan, age) }
            else
              r_children * price * (rate_plan.child_price_multiplier || 1.to_d)
            end

          price = adults_cost + children_cost

          if r_pax == 1
            supplement = rate&.single_supplement || rate_plan.single_supplement || 0.to_d
            price += supplement
          end
        else
          # Per-room sell mode with extra pax charges
          base_occ = rate&.base_occupancy || rate_plan&.base_occupancy || 2
          extra_charge = rate&.extra_pax_charge || rate_plan&.extra_pax_charge || 0.to_d

          billable_pax = r_adults + r_children
          if billable_pax > base_occ && extra_charge.positive?
            extra_guests = billable_pax - base_occ
            price += extra_guests * extra_charge
          end
        end

        nightly_total += price

        snapshot_data = if rate.present?
          rate.as_json.merge("price" => price.to_d.to_s("F"), "source" => "room_rate")
        else
          {
            "date" => date,
            "price" => price.to_d.to_s("F"),
            "currency" => currency,
            "rate_plan_id" => rate_plan&.id,
            "room_type_id" => room_type.id,
            "applied_rule_type" => "base",
            "source" => "base_price_fallback"
          }
        end

        complete_rates_by_date[date] = snapshot_data

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
        total_price: nightly_total * room_count,
        nightly_price: nightly_total / (nights.nonzero? || 1),
        nightly_rates: complete_rates_by_date,
        winning_rule: winning_rule
      )
    end

    def nightly_price_for(date, rate, room_type, rate_plan)
      std_rate = nil

      if rate.nil? || rate.rate_plan_id.nil?
        std_rate = standard_rate_for(date, room_type)
        if std_rate.present?
          return nil if std_rate.stop_sell?
          return nil if date == stay_dates.first && std_rate.closed_to_arrival?
          return nil if date == stay_dates.last && std_rate.closed_to_departure?
          return nil if std_rate.min_stay.present? && nights < std_rate.min_stay
          return nil if std_rate.max_stay.present? && nights > std_rate.max_stay
        end
      end

      if rate.present?
        # 1. Check Restrictions
        return nil if rate.stop_sell?
        return nil if date == stay_dates.first && rate.closed_to_arrival?
        return nil if date == stay_dates.last && rate.closed_to_departure?
        return nil if rate.min_stay.present? && nights < rate.min_stay
        return nil if rate.max_stay.present? && nights > rate.max_stay

        # 2. Resolve Price
        if @corporate_rate && rate.corporate_price.present?
          rate.corporate_price
        else
          rate.price
        end
      else
        # 3. Fallback to the Standard Rate's price (or the room type's flat
        # base price), transformed through the rate plan's derived pricing
        # (multiplier/offset) when applicable.
        anchor = std_rate&.price || room_type.base_price.presence
        derive_if_needed(rate_plan, room_type, anchor)
      end
    end

    def derive_if_needed(rate_plan, room_type, anchor_price)
      return anchor_price if rate_plan.blank? || anchor_price.nil?

      rtrp = room_type_rate_plan_for(room_type, rate_plan)
      return anchor_price unless rtrp&.derives_price?

      rtrp.derive_price(anchor_price) || anchor_price
    end

    def room_type_rate_plan_for(room_type, rate_plan)
      @room_type_rate_plans_by_pair ||= {}
      @room_type_rate_plans_by_pair[[ room_type.id, rate_plan.id ]] ||=
        room_type.room_type_rate_plans.includes(:rate_plan).find { |rtrp| rtrp.rate_plan_id == rate_plan.id }
    end

    def standard_rate_for(date, room_type)
      @standard_rates ||= {}
      @standard_rates[room_type.id] ||= begin
        standard_plan = room_type.standard_rate_plan
        if standard_plan
          room_type.room_rates.select { |rr| rr.rate_plan_id == standard_plan.id }.index_by(&:date)
        else
          {}
        end
      end
      @standard_rates[room_type.id][date]
    end
  end
end
