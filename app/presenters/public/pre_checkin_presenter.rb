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
      "#{booking.booking_rooms.sum(&:quantity)} room(s)"
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

    def hours_options
      (1..12).to_a
    end

    def minutes_options
      (0..59).map { |m| m.to_s.rjust(2, "0") }
    end
  end
end
