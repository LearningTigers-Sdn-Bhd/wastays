# frozen_string_literal: true

module Bookings
  module PaymentInstalments
    # Putting a refunded stage back on the agent, with a new deadline. The
    # correction path for a refund made in error, or for an agent who is to pay
    # again. What happened before stays in the audit log; the row starts over.
    class Reopen
      Result = ApplicationResult.define(:instalment)

      def self.call(...) = new(...).call

      def initialize(instalment:, user:, due_at:)
        @instalment = instalment
        @booking = instalment.booking
        @user = user
        @due_at = due_at.respond_to?(:to_time) ? due_at.to_time : nil
      end

      def call
        error = precondition_error
        return Result.failure(error, instalment: @instalment) if error

        previous_reason = @instalment.refund_reason
        ActiveRecord::Base.transaction do
          @instalment.update!(
            status: "pending", due_at: @due_at, note: "Reopened after a refund (#{previous_reason})",
            paid_at: nil, paid_by: nil, payment_folio_transaction: nil,
            refunded_at: nil, refunded_by: nil, refund_folio_transaction: nil, refund_reason: nil
          )
          ::Bookings::SyncPaymentDeadline.call(@booking)
          audit(previous_reason)
        end

        Result.success(instalment: @instalment)
      end

      private

      def precondition_error
        return "Only a refunded stage can be reopened." unless @instalment.status_refunded?
        return "This booking is cancelled, so nothing more is owed on it." if @booking.closed?
        return "Choose a deadline in the future." if @due_at.blank? || @due_at <= Time.current

        nil
      end

      def audit(previous_reason)
        ::Bookings::RecordAuditLog.call!(
          auditable: @booking, user: @user, action_type: "payment_reopened", source: "agent_payment_panel",
          old_value: { "#{@instalment.stage_label} stage" => "refunded" },
          new_value: { "#{@instalment.stage_label} stage" => "pending", "due_at" => @due_at.iso8601 },
          reason: "Previously refunded: #{previous_reason}"
        )
      end
    end
  end
end
