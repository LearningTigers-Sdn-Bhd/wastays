require "ostruct"

module BookingEngine
  class CreateQuote
    def initialize(params)
      hotel_key = params[:hotel_id].to_s
      @hotel = Hotel.where(slug: hotel_key).first || Hotel.find(hotel_key)
      raw_allocations = params[:allocations]
      if raw_allocations.is_a?(Hash) || (defined?(ActionController::Parameters) && raw_allocations.is_a?(ActionController::Parameters))
        @allocations = raw_allocations.values
      else
        @allocations = Array(raw_allocations)
      end
      # Backward compatibility for single room selection
      if @allocations.empty? && params[:room_type_id].present?
        @allocations << { room_type_id: params[:room_type_id], quantity: params[:room_count] || 1 }
      end

      @check_in = parse_date(params[:check_in])
      @check_out = parse_date(params[:check_out])
      @adults = (params[:adults].presence || 2).to_i
      @children = (params[:children].presence || 0).to_i
      @child_ages = normalize_child_ages(params[:child_ages], @children)
      @guest_name = params[:guest_name]
      @guest_email = params[:guest_email]
      @guest_phone = params[:guest_phone]
      @special_requests = params[:special_requests]
      @display_currency = CurrencyCatalog.normalize(params[:display_currency], fallback: nil)
      @rate_plan_id = params[:rate_plan_id]
      @corporate_rate = [ true, "true", 1, "1" ].include?(params[:corporate_rate])
      @agent_account_id = params[:agent_account_id]
    end

    def call
      validation_error = validate_dates
      return OpenStruct.new(success?: false, message: validation_error) if validation_error.present?

      # 1. Expand allocations into individual rooms
      flat_rooms = []
      @allocations.each do |alloc|
        begin
          room_type = @hotel.room_types.find(alloc[:room_type_id] || alloc["room_type_id"])
          quantity = (alloc[:quantity] || alloc["quantity"]).to_i
          quantity.times { flat_rooms << room_type }
        rescue ActiveRecord::RecordNotFound
          return OpenStruct.new(success?: false, message: "Invalid room type selected.")
        end
      end

      return OpenStruct.new(success?: false, message: "No rooms selected.") if flat_rooms.empty?

      BookingQuote.transaction do
        # 1. Revalidate availability
        availability_service = BookingEngine::AvailabilityService.new(
          check_in: @check_in,
          check_out: @check_out,
          adults: @adults,
          children: @children,
          corporate_rate: @corporate_rate
        )

        # 2. Distribute guests
        flat_rooms = flat_rooms.sort_by { |rt| -rt.max_capacity }
        occupancies = availability_service.send(:distribute_guests, @adults, @children, flat_rooms, child_ages: @child_ages)
        if occupancies.nil?
          return OpenStruct.new(success?: false, message: "The selected rooms do not have enough capacity or require more adults to supervise each room.")
        end

        # Group rooms by [room_type, adults, children, child_ages] so rooms with
        # the same headcount but different child ages (and thus different prices) don't
        # get incorrectly batched together.
        grouped_allocations = Hash.new(0)
        occupancies.each do |occ|
          grouped_allocations[[ occ[:room_type], occ[:adults], occ[:children], occ[:child_ages].to_a.sort ]] += 1
        end

        allocation_data = []
        total_quote_amount = 0.to_d
        quote_currency = nil

        grouped_allocations.each do |(room_type, r_adults, r_children, r_child_ages), quantity|
          rate_plan = if @hotel.pax_pricing_only?
            @rate_plan_id.present? ? room_type.rate_plans.where(sell_mode: "per_person").find_by(id: @rate_plan_id) : nil
          else
            @rate_plan_id.present? ? room_type.rate_plans.find_by(id: @rate_plan_id) : nil
          end
          pricing_summary = availability_service.pricing_summary_for(
            room_type,
            rate_plan: rate_plan,
            adults: r_adults,
            children: r_children,
            room_count: 1,
            child_ages: r_child_ages
          )

          if pricing_summary.blank?
            return OpenStruct.new(success?: false, message: "No valid rate for room #{room_type.name} with selected occupancy.")
          end

          # Check inventory
          stay_dates_list = (@check_in...@check_out).to_a
          inventories = room_type.room_inventories.select { |inv| stay_dates_list.include?(inv.date) }
          total_qty_needed = grouped_allocations.select { |(rt, _a, _c, _ages), _q| rt.id == room_type.id }.sum { |_, q| q }
          unless inventories.count == stay_dates_list.count && inventories.all? { |inv| inv.status == "open" && inv.quantity >= total_qty_needed }
            return OpenStruct.new(success?: false, message: "Room #{room_type.name} is no longer available.")
          end

          quote_currency ||= pricing_summary[:currency]
          subtotal = pricing_summary[:nightly_price] * quantity * stay_dates_list.count
          total_quote_amount += subtotal

          allocation_data << {
            room_type: room_type,
            quantity: quantity,
            subtotal: subtotal,
            pricing_summary: pricing_summary,
            adults: r_adults,
            children: r_children,
            child_ages: r_child_ages,
            rate_plan: pricing_summary[:rate_plan]
          }
        end

        display_snapshot = display_snapshot_for(total_quote_amount, quote_currency)

        # 3. Create Quote with snapshots
        quote = BookingQuote.new(
          hotel: @hotel,
          check_in: @check_in,
          check_out: @check_out,
          adults: @adults,
          children: @children,
          total_amount: total_quote_amount,
          currency: quote_currency,
          display_currency: display_snapshot[:currency],
          display_total_amount: display_snapshot[:amount],
          display_exchange_rate: display_snapshot[:rate],
          display_rate_source: display_snapshot[:source],
          expires_at: 15.minutes.from_now,
          hotel_snapshot: @hotel.booking_snapshot,
          cancellation_policy_snapshot: @hotel.property_policy&.cancellation_policy,
          guest_name: @guest_name,
          guest_email: @guest_email,
          guest_phone: @guest_phone,
          special_requests: @special_requests,
          agent_account_id: @agent_account_id
        )

        if quote.save
          # 4. Create Quote Items
          allocation_data.each do |data|
            quote.booking_quote_items.create!(
              room_type: data[:room_type],
              quantity: data[:quantity],
              subtotal: data[:subtotal],
              room_type_snapshot: data[:room_type].as_json,
              nightly_rate_snapshot: data[:pricing_summary][:nightly_rates].transform_values(&:as_json),
              occupancy_snapshot: {
                max_adults: data[:room_type].max_adults,
                max_children: data[:room_type].max_children,
                actual_occupancy: data[:adults] + data[:children],
                adults: data[:adults],
                children: data[:children],
                child_ages: data[:child_ages] || [],
                child_age_bands: (data[:child_ages] || []).map { |age|
                  band = data[:rate_plan]&.band_for_age(age)
                  {
                    age: age,
                    band_id: band&.id,
                    band_label: band&.label,
                    pricing_mode: band&.pricing_mode || "multiplier",
                    price_value: (band&.price_value || data[:rate_plan]&.child_price_multiplier).to_s
                  }
                }
              }
            )
          end

          # Record Audit Log
          Bookings::RecordAuditLog.call(
            auditable: quote,
            action_type: "create"
          )

          # 5. Place Inventory Hold
          hold_service = BookingEngine::HoldInventory.new(quote)
          if hold_service.call
            OpenStruct.new(success?: true, quote: quote)
          else
            raise ActiveRecord::Rollback, "Failed to hold inventory"
          end
        else
          OpenStruct.new(success?: false, message: quote.errors.full_messages.to_sentence)
        end
      end
    rescue => e
      OpenStruct.new(success?: false, message: "An error occurred: #{e.message}")
    end

    private

    def normalize_child_ages(raw_ages, children_count)
      ages = Array(raw_ages).map(&:to_i)
      return [] if ages.size != children_count
      ages
    end

    def parse_date(date_param)
      return date_param if date_param.is_a?(Date)
      return nil if date_param.blank?

      Date.parse(date_param)
    rescue ArgumentError
      nil
    end

    def validate_dates
      return "Please select check-in and check-out dates." if @check_in.blank? || @check_out.blank?
      return "Check-out date must be after check-in date." if @check_out <= @check_in

      nil
    end

    def display_snapshot_for(total_amount, quote_currency)
      display_currency = @display_currency.presence || quote_currency
      conversion = CurrencyConverter.convert(total_amount, from: quote_currency, to: display_currency, hotel: @hotel)
      return { currency: quote_currency, amount: total_amount, rate: 1.to_d, source: "charge_currency" } if conversion.blank?

      {
        currency: display_currency,
        amount: conversion.amount,
        rate: conversion.rate,
        source: conversion.source
      }
    end
  end
end
