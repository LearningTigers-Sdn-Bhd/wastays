# frozen_string_literal: true

module Public
  module Concierge
    # The stay facts the page shows, and the actions it offers.
    #
    # The presenter decides what is available. The views only lay it out, so the
    # design session that follows can rebuild the markup without touching a
    # rule.
    class StayPresenter
      def initialize(stay_access:, expires_at: nil, view: nil)
        @stay_access = stay_access
        @expires_at = expires_at
        @view = view
      end

      def booking = @booking ||= stay_access.booking
      def hotel = booking.hotel

      def in_house? = booking.status.in?(Booking::IN_HOUSE_STATUSES)
      def checked_out? = booking.status == "completed"

      def greeting_name
        first = booking.guest_name.to_s.strip.split.first
        first.presence || "Guest"
      end

      def room_label
        booking.room_numbers.presence || "To be assigned"
      end

      def nights
        (booking.check_out.to_date - booking.check_in.to_date).to_i
      end

      # Where the guest is in the stay, on the hotel's own date. Nothing once
      # the guest has checked out: the card says that itself.
      def stay_progress_label
        return unless in_house?

        today = hotel.current_business_date || hotel.business_date_for
        return "Check-out today" if today >= booking.check_out.to_date

        night = (today - booking.check_in.to_date).to_i + 1
        "Night #{night.clamp(1, nights)} of #{nights}"
      end

      def confirmation_code
        booking.confirmation_token.to_s.upcase
      end

      def booking_reference_number
        booking.formatted_reservation_number
      end

      def status_label
        booking.status.humanize
      end

      # ------------------------------------------------------------- availables

      def can_request_check_out?
        in_house? && booking.check_out_requests.open_tasks.none?
      end

      def check_out_pending?
        booking.check_out_requests.open_tasks.any?
      end

      def can_send_request?
        ::Bookings::Occupancy.accepts_guest_requests?(booking)
      end

      def can_request_refund?
        booking.refund_request.blank? || booking.refund_request.rejected?
      end

      def refund_request = booking.refund_request

      def can_request_e_invoice?
        booking.e_invoice_guest_request_possible?
      end

      def e_invoice_ready?
        booking.latest_ready_guest_e_invoice_submission.present?
      end

      def chat_available?
        hotel.concierge_chat_available?
      end

      # A stay page keeps the invoice after check-out, which is the whole point
      # of the grace period.
      def invoice_available?
        checked_out?
      end

      def grace_period_ends_at = @expires_at

      private

      attr_reader :stay_access, :view
    end
  end
end
