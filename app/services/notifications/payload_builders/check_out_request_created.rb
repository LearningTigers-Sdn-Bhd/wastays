# frozen_string_literal: true

module Notifications
  module PayloadBuilders
    class CheckOutRequestCreated
      def initialize(check_out_request:)
        @request = check_out_request
        @booking = check_out_request.booking
      end

      def call
        {
          notification_type: "check_out_request_created",
          trigger_event: "check_out_request_created",
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          guest_name: @booking.guest_name,
          guest_phone: @booking.guest_phone,
          hotel_name: @booking.hotel.name,
          check_out: @booking.check_out.iso8601,
          guest_notes: @request.guest_notes,
          check_out_request_id: @request.id
        }
      end
    end
  end
end
