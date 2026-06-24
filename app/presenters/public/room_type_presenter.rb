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

    def display_total_price(display_currency)
      return unless pricing_summary[:total_price]
      @view_context.display_amount(pricing_summary[:total_price],
                                   quote_currency: pricing_summary[:currency],
                                   display_currency: display_currency,
                                   hotel: @hotel)
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

    def rate_plan_infant_multiplier
      pricing_summary[:rate_plan]&.infant_price_multiplier
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
  end
end
