# frozen_string_literal: true

module Notifications
  module PayloadBuilders
    # One payload for all four agent payment mails -- reminder, approved,
    # rejected, released. They differ in subject and a sentence of copy, not in
    # what they have to state, so four near-identical builders would be four
    # places to forget the deadline or the currency.
    #
    # Everything the mail needs is copied in rather than read back from the
    # booking at send time. A delivery is a record of what the agent was told,
    # and a deadline that has since moved must not rewrite the history of what
    # was sent.
    class AgentPaymentNotice
      def initialize(booking:, notification_type:, trigger_event:, extra: {})
        @booking = booking
        @notification_type = notification_type
        @trigger_event = trigger_event
        @extra = extra
      end

      def call
        payment = CorporatePortal::BookingPaymentPresenter.new(@booking)

        {
          notification_type: @notification_type,
          trigger_event: @trigger_event,
          booking_id: @booking.id,
          reservation_number: @booking.formatted_reservation_number,
          guest_name: @booking.guest_name,
          hotel_name: @booking.hotel.name,
          agency_name: @booking.hotel_corporate_account&.corporate_account&.name,
          recipient_name: Notifications::AgentRecipient.name_for(@booking),
          recipient_email: Notifications::AgentRecipient.email_for(@booking),
          check_in: @booking.check_in.iso8601,
          check_out: @booking.check_out.iso8601,
          amount: @booking.total_amount.to_s,
          currency: @booking.currency,
          amount_label: payment.amount_label,
          # Stated with its zone: the agent is often not in the hotel's.
          payment_due_at: @booking.payment_due_at&.iso8601,
          payment_due_label: payment.due_at_label,
          time_left_label: payment.time_left_label,
          pay_url: pay_url
        }.merge(@extra).compact
      end

      private

      # Where the agent goes to act on it. Deep-linked to the submission form for
      # this booking, because a reminder that only says "log in" wastes the time
      # it is warning them about.
      def pay_url
        options = Rails.application.config.action_mailer.default_url_options.to_h
        return if options[:host].blank?

        Rails.application.routes.url_helpers.new_corporate_ar_payment_submission_url(
          **options, booking_id: @booking.id
        )
      rescue StandardError
        nil
      end
    end
  end
end
