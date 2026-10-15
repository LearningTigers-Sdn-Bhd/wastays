# frozen_string_literal: true

module Bookings
  module PaymentInstalments
    # Giving a stage's money back: an overpayment, a payment taken in error, or
    # the hotel's own mistake. A negative payment is posted to the folio and the
    # stage is marked refunded, with who did it and why.
    #
    # A refunded stage is no longer owed, so the booking is not released for it.
    # If the agent should still pay it, reopen it afterwards with a new deadline.
    class Refund
      include FolioPosting

      Result = ApplicationResult.define(:instalment)

      def self.call(...) = new(...).call

      def initialize(instalment:, user:, refund_source:, reason:)
        @instalment = instalment
        @booking = instalment.booking
        @user = user
        @refund_source = refund_source.to_s
        @reason = reason.to_s.strip
      end

      def call
        error = precondition_error
        return Result.failure(error, instalment: @instalment) if error

        ActiveRecord::Base.transaction do
          transaction = post_to_folio!(
            booking: @booking, signed_amount: -@instalment.amount, category: "refund", user: @user,
            description: "Refund of agent #{@instalment.stage_label.downcase}: #{@reason}",
            metadata: { instalment_id: @instalment.id, refund_source: @refund_source, reason: @reason, recorded_by_user_id: @user&.id }
          )
          @instalment.update!(
            status: "refunded", refunded_at: Time.current, refunded_by: @user,
            refund_folio_transaction: transaction, refund_reason: @reason
          )
          ::Bookings::SyncPaymentDeadline.call(@booking)
          audit
        end

        Result.success(instalment: @instalment)
      rescue FolioPosting::PostingFailed => e
        Result.failure(e.message, instalment: @instalment)
      end

      private

      def precondition_error
        return "Only a stage that has been paid can be refunded." unless @instalment.status_paid?
        return "Say why it is being refunded." if @reason.blank?
        return "Choose where the refund is paid from." unless ::Folios::Payments::RefundSource.valid?(@refund_source)
        return "Only #{format('%.2f', progress.paid_total)} is held on this booking, less than this stage." if @instalment.amount > progress.paid_total

        nil
      end

      def progress = @progress ||= ::Bookings::PaymentProgress.new(@booking)

      def audit
        ::Bookings::RecordAuditLog.call!(
          auditable: @booking, user: @user, action_type: "refund_completed", source: "agent_payment_panel",
          old_value: { "#{@instalment.stage_label} stage" => "paid" },
          new_value: { "#{@instalment.stage_label} stage" => "refunded", "amount" => @instalment.amount.to_s("F"), "source" => @refund_source },
          reason: @reason
        )
      end
    end
  end
end
