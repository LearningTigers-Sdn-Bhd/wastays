# frozen_string_literal: true

module Notifications
  module PayloadBuilders
    class PostStayReviewRequest
      def initialize(booking:, review_link:)
        @booking = booking
        @review_link = review_link.to_s.strip
      end

      def call
        raise ArgumentError, "Review link is missing" if @review_link.blank?

        {
          booking_id: @booking.id,
          confirmation_token: @booking.confirmation_token,
          guest_name: @booking.guest_name,
          guest_email: @booking.guest_email,
          guest_phone: @booking.guest_phone,
          hotel_name: @booking.hotel.name,
          check_out: @booking.check_out,
          checked_out_at: @booking.checked_out_at&.iso8601,
          review_link: @review_link,
          trigger_event: "booking_completed",
          notification_type: "post_stay_review_request"
        }
      end
    end
  end
end
