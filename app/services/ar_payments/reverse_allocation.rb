# frozen_string_literal: true

require "ostruct"

module ArPayments
  class ReverseAllocation
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(allocation:, user:, reason:)
      @allocation = allocation
      @user = user
      @reason = reason.to_s.strip
    end

    def call
      return failure("Reversal reason is required.") if @reason.blank?

      reversal = nil
      ActiveRecord::Base.transaction do
        @allocation.lock!
        @allocation.ar_payment.lock!
        @allocation.ar_invoice.lock!
        raise ActiveRecord::Rollback, "This allocation has already been reversed." if @allocation.reload.reversed?

        reversal = @allocation.create_reversal!(
          reversed_by: @user,
          reason: @reason,
          reversed_at: Time.current,
          metadata: reversal_metadata
        )
        restore_invoice!
        record_audit_event!(reversal)
      rescue ActiveRecord::Rollback => e
        return failure(e.message)
      end

      success(reversal)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def restore_invoice!
      invoice = @allocation.ar_invoice
      paid_amount = invoice.paid_amount.to_d - @allocation.amount.to_d
      outstanding_amount = invoice.outstanding_amount.to_d + @allocation.amount.to_d
      raise ActiveRecord::Rollback, "Invoice paid amount cannot become negative." if paid_amount.negative?

      invoice.update!(
        paid_amount: paid_amount,
        outstanding_amount: outstanding_amount,
        status: restored_status(invoice, paid_amount)
      )
    end

    def restored_status(invoice, paid_amount)
      return "overdue" if invoice.due_on < invoice.hotel.current_business_date
      return "partially_paid" if paid_amount.positive?

      "open"
    end

    def reversal_metadata
      {
        ar_payment_id: @allocation.ar_payment_id,
        ar_invoice_id: @allocation.ar_invoice_id,
        amount: @allocation.amount.to_s("F")
      }
    end

    def record_audit_event!(reversal)
      payment = @allocation.ar_payment
      FinancialControls::AuditEventRecorder.call!(
        hotel: payment.hotel,
        business_date: payment.hotel.current_business_date,
        event_type: "ar_payment_allocation_reversed",
        source: "ar_payments",
        actor: @user,
        amount: @allocation.amount,
        currency: payment.currency,
        reason: @reason,
        metadata: {
          ar_payment_id: payment.id,
          ar_payment_allocation_id: @allocation.id,
          ar_payment_allocation_reversal_id: reversal.id,
          ar_invoice_id: @allocation.ar_invoice_id,
          invoice_number: @allocation.ar_invoice.invoice_number
        }
      )
    end

    def success(reversal)
      OpenStruct.new(success?: true, reversal: reversal, error: nil)
    end

    def failure(error)
      OpenStruct.new(success?: false, reversal: nil, error: error)
    end
  end
end
