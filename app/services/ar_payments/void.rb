# frozen_string_literal: true

require "ostruct"

module ArPayments
  # Voids a payment recorded in error. The payment row is immutable, so the
  # void is a separate record. Only a payment with no active allocation and no
  # gateway charge behind it can be voided.
  class Void
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(payment:, user:, reason:)
      @payment = payment
      @user = user
      @reason = reason.to_s.strip
    end

    def call
      return failure("Void reason is required.") if @reason.blank?

      void = nil
      ActiveRecord::Base.transaction do
        @payment.lock!
        raise ActiveRecord::Rollback, "This payment is already voided." if ArPaymentVoid.exists?(ar_payment_id: @payment.id)
        raise ActiveRecord::Rollback, "Reverse the active allocations before voiding this payment." if @payment.ar_payment_allocations.active.exists?
        raise ActiveRecord::Rollback, "This payment came from a gateway charge. Refund it through the gateway." if @payment.gateway_payment?

        void = ArPaymentVoid.create!(
          ar_payment: @payment,
          voided_by: @user,
          reason: @reason,
          voided_at: Time.current,
          metadata: { amount: @payment.amount.to_s("F"), currency: @payment.currency }
        )
        @payment.receipt&.update!(status: "voided") unless @payment.receipt&.voided?
        record_audit_event!(void)
      rescue ActiveRecord::Rollback => e
        return failure(e.message)
      end

      success(void)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def record_audit_event!(void)
      FinancialControls::AuditEventRecorder.call!(
        hotel: @payment.hotel,
        business_date: @payment.hotel.current_business_date,
        event_type: "ar_payment_voided",
        source: "ar_payments",
        actor: @user,
        amount: @payment.amount,
        currency: @payment.currency,
        reason: @reason,
        metadata: {
          ar_payment_id: @payment.id,
          ar_payment_void_id: void.id,
          reference_number: @payment.reference_number
        }
      )
    end

    def success(void)
      OpenStruct.new(success?: true, void: void, error: nil)
    end

    def failure(error)
      OpenStruct.new(success?: false, void: nil, error: error)
    end
  end
end
