# frozen_string_literal: true

module Notifications
  module PayloadBuilders
    class CheckInConfirmation
      def initialize(booking:)
        @booking = booking
      end

      def call
        {
          notification_type: "check_in_confirmation",
          trigger_event: "booking_checked_in",
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          guest_name: @booking.guest_name,
          guest_phone: @booking.guest_phone,
          guest_email: @booking.guest_email,
          hotel_name: @booking.hotel.name,
          check_in: @booking.check_in.iso8601,
          check_out: @booking.check_out.iso8601,
          checked_in_at: @booking.checked_in_at&.iso8601,
          room_numbers: @booking.room_numbers
        }
      end
    end
  end
end
