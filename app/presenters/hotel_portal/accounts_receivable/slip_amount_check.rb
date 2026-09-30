# frozen_string_literal: true

module HotelPortal
  module AccountsReceivable
    # What staff need beside an agent's slip before approving it: what the slip
    # says was sent, what the booking asks for now, and whether the two agree.
    # Approving posts the slip's amount to the folio, so a slip claiming more or
    # less than the booking asks for is the thing to catch here.
    class SlipAmountCheck
      def initialize(submission)
        @submission = submission
        @booking = submission.booking
      end

      def applicable? = @booking.present?

      def claimed_label = money(@submission.amount)

      # "MYR 500.00 (deposit)" for a scheduled booking, else everything owed.
      def due_label
        stage = progress.next_instalment
        label = money(progress.amount_due_now || progress.owed_total)
        stage ? "#{label} (#{stage.stage_label.downcase})" : label
      end

      def total_label = money(@booking.total_amount)

      # Nil when the slip fits what the booking asks for.
      def warning
        problem = progress.amount_problem(@submission.amount, currency: @booking.currency)
        return if problem.blank?

        "This slip says #{claimed_label}, which #{problem}. Check the slip before approving."
      end

      private

      def progress = @progress ||= ::Bookings::PaymentProgress.new(@booking)

      def money(amount)
        "#{@booking.currency} #{ActiveSupport::NumberHelper.number_to_rounded(amount, precision: 2, delimiter: ',')}"
      end
    end
  end
end
