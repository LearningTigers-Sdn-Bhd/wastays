# frozen_string_literal: true

module Notifications
  module PayloadBuilders
    class ConciergeRequestCreated
      def initialize(request:, kind:)
        @request = request
        @kind = kind.to_s
        @booking = request.booking
      end

      def call
        details = @kind == "housekeeping" ? @request.request_details : @request.complaint_details
        {
          notification_type: "concierge_request_created",
          trigger_event: "concierge_request_created",
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          guest_name: @booking.guest_name,
          guest_phone: @booking.guest_phone,
          hotel_name: @booking.hotel.name,
          request_kind: @kind,
          request_details: details,
          request_id: @request.id
        }
      end
    end
  end
end
