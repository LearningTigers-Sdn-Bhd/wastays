# frozen_string_literal: true

module Public
  class RoomTypePresenter < SimpleDelegator
    def initialize(room_type, hotel, availability_service, view_context)
      @room_type = room_type
      @hotel = hotel
      @availability_service = availability_service
      @view_context = view_context
      super(room_type)
    end

    def pricing_summary
      @pricing_summary ||= @availability_service&.pricing_summary_for(@room_type) || {}
    end

    def single_room_pricing_summary
      @single_room_pricing_summary ||= @availability_service&.pricing_summary_for(@room_type, room_count: 1) || {}
    end

    def display_total_price(display_currency)
      return unless pricing_summary[:total_price]
      @view_context.display_amount(pricing_summary[:total_price],
                                   quote_currency: pricing_summary[:currency],
                                   display_currency: display_currency,
                                   hotel: @hotel)
    end

    def display_single_room_total_price(display_currency)
      return unless single_room_pricing_summary[:total_price]
      @view_context.display_amount(single_room_pricing_summary[:total_price],
                                   quote_currency: single_room_pricing_summary[:currency],
                                   display_currency: display_currency,
                                   hotel: @hotel)
    end

    def single_room_total_price_value
      single_room_pricing_summary[:total_price]&.to_f || 0.0
    end

    def available_quantity
      return 0 unless @availability_service
      check_in = @availability_service.check_in
      check_out = @availability_service.check_out
      return 0 if check_in.blank? || check_out.blank? || check_out <= check_in

      stay_dates = (check_in...check_out).to_a
      inventories = @room_type.room_inventories.select { |inv| stay_dates.include?(inv.date) }
      return 0 unless inventories.count == stay_dates.count
      return 0 if inventories.any? { |inv| inv.status != "open" }

      inventories.map(&:quantity).min || 0
    end

    def rate_plan_name
      pricing_summary[:rate_plan_name].presence || "Best available rate"
    end

    def stay_restriction_error
      @availability_service&.stay_restriction_error_message(@room_type)
    end

    def per_pax_billing?
      pricing_summary[:rate_plan]&.sell_mode == "per_person"
    end

    def rate_plan_base_occupancy
      pricing_summary[:rate_plan]&.base_occupancy
    end

    def rate_plan_single_supplement(display_currency)
      rp = pricing_summary[:rate_plan]
      return unless rp && rp.single_supplement.present? && rp.single_supplement > 0
      @view_context.display_amount(rp.single_supplement,
                                   quote_currency: pricing_summary[:currency],
                                   display_currency: display_currency,
                                   hotel: @hotel)
    end

    def rate_plan_extra_pax_charge(display_currency)
      rp = pricing_summary[:rate_plan]
      return unless rp && rp.extra_pax_charge.present? && rp.extra_pax_charge > 0
      @view_context.display_amount(rp.extra_pax_charge,
                                   quote_currency: pricing_summary[:currency],
                                   display_currency: display_currency,
                                   hotel: @hotel)
    end

    def rate_plan_child_multiplier
      pricing_summary[:rate_plan]&.child_price_multiplier
    end

    def stay_nights
      stay_dates.size
    end

    # Average nightly room total for every adult count this room can hold,
    # resolved by the same service the quote uses. The browser preview needs the
    # whole ladder, not one per-person figure: under an occupancy matrix a room
    # is not "adults x per-person", and each rung implies its own child anchor.
    # Averaging across nights is exact for the stay total, since percentage
    # bands are linear and flat amounts are per night.
    def pax_occupancy_nightly_prices
      @pax_occupancy_nightly_prices ||= begin
        rate_plan = pricing_summary[:rate_plan]
        dates = stay_dates

        if rate_plan.blank? || !per_pax_billing? || dates.empty?
          {}
        else
          (1..@room_type.max_adults.to_i).each_with_object({}) do |count, prices|
            total = dates.sum do |date|
              amount = nightly_amount_for(rate_plan, date, count)
              break nil if amount.nil?
              amount
            end

            prices[count] = (total / dates.size).to_f if total
          end
        end
      end
    end

    def pax_rate_value
      return 0.0 unless pricing_summary[:rate_plan] && @availability_service

      # Prefer the rung the guest actually searched for — RoomRate#price is the
      # max-occupancy room total, which would read as a wildly high "per person".
      searched_adults = @availability_service.adults.to_i
      rung = pax_occupancy_nightly_prices[searched_adults]
      return (rung / searched_adults).round(2) if rung && searched_adults.positive?

      rp = pricing_summary[:rate_plan]
      currency = pricing_summary[:currency]

      dates = stay_dates
      return 0.0 if dates.empty?

      rates_by_date = @room_type.room_rates.select { |rr| dates.include?(rr.date) && rr.rate_plan_id == rp.id && rr.currency == currency }.index_by(&:date)

      total_base = dates.sum do |date|
        rate = rates_by_date[date]
        rate&.price || @room_type.base_price || 0.to_d
      end

      (total_base / dates.size).to_f
    end

    def display_pax_rate(display_currency)
      rate = pax_rate_value
      return unless rate > 0
      @view_context.display_amount(rate,
                                   quote_currency: pricing_summary[:currency],
                                   display_currency: display_currency,
                                   hotel: @hotel)
    end

    def details_json
      {
        name: name,
        description: description,
        max_adults: max_adults,
        max_children: max_children,
        photos: photos.map { |p| @view_context.url_for(p) },
        room_amenities: amenities.map { |id|
          amenity = Hotel::ROOM_AMENITIES_MAP[id]
          next nil unless amenity
          amenity.merge(category_icon: @view_context.category_icon(amenity[:category]))
        }.compact,
        hotel_amenities: @hotel.amenities.map { |id|
          amenity = Hotel::HOTEL_AMENITIES_MAP[id]
          next nil unless amenity
          amenity.merge(category_icon: @view_context.category_icon(amenity[:category]))
        }.compact
      }.to_json
    end

    def photo_url
      photos.attached? ? @view_context.url_for(photos.first) : nil
    end

    private

    def stay_dates
      @stay_dates ||= @availability_service ? @availability_service.send(:stay_dates) : []
    end

    def nightly_amount_for(rate_plan, date, adults)
      Rates::ResolveEffectiveNightlyPrice.call(
        room_type: @room_type,
        rate_plan: rate_plan,
        date: date,
        currency: pricing_summary[:currency],
        adults: adults,
        children: 0,
        room_rates: @room_type.room_rates
      ).amount
    end
  end
end
