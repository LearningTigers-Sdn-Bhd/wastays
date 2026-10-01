# frozen_string_literal: true

module Bookings
  module PaymentInstalments
    # Staff recording that an agent has paid a stage: cash, or a transfer that
    # never came through the portal. The money is posted to the folio like any
    # other payment, which settles the stage; the panel never marks a stage paid
    # without money behind it.
    #
    # Stages are taken in order. Paying the balance while the deposit is still
    # owed would leave the schedule saying the opposite of what the folio does.
    class MarkPaid
      include FolioPosting

      Result = ApplicationResult.define(:instalment)

      PAYMENT_METHODS = {
        "bank_transfer" => "Bank transfer",
        "cash" => "Cash",
        "card_terminal" => "Card terminal"
      }.freeze

      def self.call(...) = new(...).call

      def initialize(instalment:, user:, payment_method:, reference:, note: nil)
        @instalment = instalment
        @booking = instalment.booking
        @user = user
        @payment_method = payment_method.to_s
        @reference = reference.to_s.strip
        @note = note.to_s.strip.presence
      end

      def call
        error = precondition_error
        return Result.failure(error, instalment: @instalment) if error

        ActiveRecord::Base.transaction do
          post_payment
          ::Bookings::SettlePaymentInstalments.call(booking: @booking, folio_transaction: @transaction, user: @user)
          raise ActiveRecord::Rollback, "not settled" unless @instalment.reload.status_paid?

          @instalment.update!(note: [ "Marked paid (#{PAYMENT_METHODS.fetch(@payment_method).downcase}, ref #{@reference})", @note ].compact.join(". "))
          audit
        end

        return Result.failure("The payment was recorded but did not cover this stage.", instalment: @instalment) unless @instalment.reload.status_paid?

        Result.success(instalment: @instalment)
      rescue FolioPosting::PostingFailed => e
        Result.failure(e.message, instalment: @instalment)
      end

      private

      def progress = @progress ||= ::Bookings::PaymentProgress.new(@booking)

      def precondition_error
        return "Only a stage still owed can be marked paid." unless @instalment.status_pending?
        return "This booking is cancelled, so nothing more is owed on it." if @booking.closed?
        return "Record the earlier stage first." if earlier_stage_pending?
        return "Choose how it was paid." unless PAYMENT_METHODS.key?(@payment_method)
        return "Enter the reference (receipt or transfer number)." if @reference.blank?

        nil
      end

      def earlier_stage_pending?
        @booking.payment_instalments.pending.where("position < ?", @instalment.position).exists?
      end

      # Nothing is posted when the folio already covers the stage (a payment the
      # schedule has not caught up with): the stage is simply settled.
      def post_payment
        amount = progress.outstanding_through(@instalment)
        return unless amount.positive?

        @transaction = post_to_folio!(
          booking: @booking, signed_amount: amount, category: "booking_payment", user: @user,
          description: "Agent #{@instalment.stage_label.downcase} recorded (#{PAYMENT_METHODS.fetch(@payment_method).downcase}, ref #{@reference})",
          metadata: { instalment_id: @instalment.id, payment_method: @payment_method, reference: @reference, recorded_by_user_id: @user&.id }
        )
      end

      def audit
        ::Bookings::RecordAuditLog.call!(
          auditable: @booking, user: @user, action_type: "payment_recorded", source: "agent_payment_panel",
          old_value: { "#{@instalment.stage_label} stage" => "pending" },
          new_value: { "#{@instalment.stage_label} stage" => "paid", "amount" => @instalment.amount.to_s("F"), "reference" => @reference, "method" => @payment_method },
          reason: @note
        )
      end
    end
  end
end
