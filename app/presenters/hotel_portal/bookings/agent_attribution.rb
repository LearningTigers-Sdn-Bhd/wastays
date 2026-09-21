# frozen_string_literal: true

module HotelPortal
  module Bookings
    # What the hotel is told about a booking an agency made: which agency, who
    # there, when -- and whether they have paid for it yet.
    #
    # Two presenters feed the same badge (the reservations list and the booking
    # workspace), so the hash is built once here rather than twice. The payment
    # half comes from CorporatePortal::BookingPaymentPresenter, the same object
    # the agent's own portal reads, because the desk answering "have they paid?"
    # and the agent looking at their deadline must never be given different
    # answers.
    #
    # Returns nil unless `corporate_booked_at` is set, so corporate bookings made
    # before attribution was recorded stay unmarked rather than claiming an
    # author nobody wrote down.
    module AgentAttribution
      BADGE_VARIANTS = {
        overdue: :destructive,
        due: :warning,
        under_review: :info
      }.freeze

      module_function

      def for(booking, time_zone:)
        return unless agent_booking?(booking)

        payment = CorporatePortal::BookingPaymentPresenter.new(booking)

        {
          agency: booking.hotel_corporate_account&.corporate_account&.name,
          person: booking.corporate_booked_by&.name,
          booked_at: booking.corporate_booked_at.in_time_zone(time_zone).strftime("%d %b %Y %H:%M"),
          payment_state: payment.state,
          payment_label: payment.badge_label,
          payment_due_label: payment.due_at_label,
          # The badge itself turns red only when rooms are genuinely at risk;
          # a paid booking looks like any other agency booking.
          badge_variant: BADGE_VARIANTS.fetch(payment.state, :accent)
        }
      end

      def agent_booking?(booking)
        booking.hotel_corporate_account_id.present? && booking.corporate_booked_at.present?
      end
    end
  end
end
