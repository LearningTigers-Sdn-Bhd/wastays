# frozen_string_literal: true

module Notifications
  module PayloadBuilders
    class PreArrivalNotification
      STAGES = %w[d2 d1].freeze

      def initialize(booking:, stage:, scheduled_for:)
        @booking = booking
        @stage = stage.to_s
        @scheduled_for = scheduled_for
      end

      def call
        raise ArgumentError, "Unsupported pre-arrival stage: #{@stage}" unless STAGES.include?(@stage)

        {
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          guest_name: @booking.guest_name,
          guest_email: @booking.guest_email,
          guest_phone: @booking.guest_phone,
          hotel_name: @booking.hotel.name,
          check_in: @booking.check_in&.iso8601,
          check_out: @booking.check_out&.iso8601,
          trigger_event: "booking_confirmed",
          notification_type: "pre_arrival_notification",
          stage: @stage,
          scheduled_for: @scheduled_for.iso8601
        }
      end
    end
  end
end
