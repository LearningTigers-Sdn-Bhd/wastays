# frozen_string_literal: true

module Public
  class PreCheckinPresenter
    attr_reader :pre_checkin, :booking, :hotel

    def initialize(pre_checkin)
      @pre_checkin = pre_checkin
      @booking = pre_checkin.booking
      @hotel = booking.hotel
    end

    def hotel_name
      hotel.name
    end

    def hotel_location
      "#{hotel.city}, #{hotel.country}"
    end

    def confirmation_token
      booking.confirmation_token
    end

    def stay_dates
      "#{booking.check_in.strftime("%d %b %Y")} - #{booking.check_out.strftime("%d %b %Y")}"
    end

    def rooms_count_label
      "#{booking.booking_rooms.count} room(s)"
    end

    def completed?
      pre_checkin.completed?
    end

    def errors
      (booking.errors.full_messages + pre_checkin.errors.full_messages).uniq
    end

    def any_errors?
      errors.any?
    end

    def document_type_options
      [ [ "Select Document", "" ] ] + Booking::DOCUMENT_TYPES
    end

    def guest_country_default
      booking.guest_country.presence || "Malaysia"
    end

    def guest_address_country_default
      booking.guest_address_country.presence || booking.guest_country.presence || "Malaysia"
    end

    HIDDEN_CLASSES = "hidden opacity-0 scale-95 -translate-y-2"

    def guest_document_type
      booking.guest_document_type
    end

    def upload_section_class
      guest_document_type.blank? ? HIDDEN_CLASSES : ""
    end

    def front_container_class
      if guest_document_type.blank?
        HIDDEN_CLASSES
      elsif guest_document_type == "passport"
        "md:col-span-2 w-full"
      else
        ""
      end
    end

    def back_container_class
      guest_document_type == "ic" ? "" : HIDDEN_CLASSES
    end

    def front_scanner_label
      guest_document_type == "passport" ? "Passport Photo Page" : "Front ID Card"
    end

    def front_scanner_height_class
      guest_document_type == "passport" ? "h-44 md:h-64 md:max-w-[480px]" : "h-44"
    end

    def hours_options
      (1..12).to_a
    end

    def minutes_options
      (0..59).map { |m| m.to_s.rjust(2, "0") }
    end
  end
end
