# frozen_string_literal: true

require "ostruct"

module ArPayments
  class AllocatePayment
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(payment:, user:, allocations:)
      @payment = payment
      @user = user
      @allocations = allocations
    end

    def call
      return failure("At least one invoice allocation is required.") if allocation_rows.empty?

      created_allocations = []
      ActiveRecord::Base.transaction do
        @payment.lock!
        invoices.each(&:lock!)

        error = validate_allocations
        raise ActiveRecord::Rollback, error if error.present?

        allocation_rows.each do |row|
          invoice = invoices_by_id.fetch(row[:invoice_id])
          allocation = @payment.ar_payment_allocations.create!(
            ar_invoice: invoice,
            amount: row[:amount],
            metadata: allocation_metadata(invoice)
          )
          update_invoice!(invoice, row[:amount])
          created_allocations << allocation
        end

        record_audit_event!(created_allocations)
      rescue ActiveRecord::Rollback => e
        return failure(e.message)
      end

      success(created_allocations)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def validate_allocations
      return "Allocation total cannot exceed the payment's unapplied balance." if allocation_total > @payment.unallocated_amount

      allocation_rows.each do |row|
        invoice = invoices_by_id[row[:invoice_id]]
        return "Invoice #{row[:invoice_id]} is not available for this payment." if invoice.blank?
        return "Allocation for AR-#{invoice.invoice_number} exceeds outstanding amount." if row[:amount] > invoice.outstanding_amount.to_d
        return "Cannot allocate payment to closed invoice AR-#{invoice.invoice_number}." unless invoice.outstanding_amount.to_d.positive? && !invoice.void?
      end

      nil
    end

    def allocation_rows
      @allocation_rows ||= normalized_allocations.to_a.filter_map do |invoice_id, amount|
        decimal = amount.to_s.presence.to_d
        next unless decimal.positive?

        { invoice_id: invoice_id.to_i, amount: decimal }
      end
    end

    def normalized_allocations
      return @allocations.to_unsafe_h if @allocations.respond_to?(:to_unsafe_h)
      return @allocations.to_h if @allocations.respond_to?(:to_h)

      @allocations
    end

    def allocation_total
      allocation_rows.sum { |row| row[:amount] }
    end

    def invoices
      @invoices ||= @payment.hotel.ar_invoices
        .with_open_balance
        .where(hotel_corporate_account: @payment.hotel_corporate_account, currency: @payment.currency)
        .where(id: allocation_rows.map { |row| row[:invoice_id] })
        .to_a
    end

    def invoices_by_id
      @invoices_by_id ||= invoices.index_by(&:id)
    end

    def update_invoice!(invoice, amount)
      paid_amount = invoice.paid_amount.to_d + amount
      outstanding_amount = invoice.outstanding_amount.to_d - amount
      invoice.update!(
        paid_amount: paid_amount,
        outstanding_amount: outstanding_amount,
        status: outstanding_amount.zero? ? "paid" : "partially_paid"
      )
    end

    def allocation_metadata(invoice)
      {
        ar_invoice_id: invoice.id,
        invoice_number: invoice.invoice_number,
        reference_number: @payment.reference_number,
        received_at: @payment.received_at.to_s,
        allocated_later: true
      }
    end

    def record_audit_event!(allocations)
      FinancialControls::AuditEventRecorder.call!(
        hotel: @payment.hotel,
        business_date: @payment.hotel.current_business_date,
        event_type: "ar_payment_allocated",
        source: "ar_payments",
        actor: @user,
        amount: allocation_total,
        currency: @payment.currency,
        metadata: {
          ar_payment_id: @payment.id,
          reference_number: @payment.reference_number,
          allocations: allocations.map do |allocation|
            {
              ar_payment_allocation_id: allocation.id,
              ar_invoice_id: allocation.ar_invoice_id,
              invoice_number: allocation.ar_invoice.invoice_number,
              amount: allocation.amount.to_s("F")
            }
          end
        }
      )
    end

    def success(allocations)
      OpenStruct.new(success?: true, allocations: allocations, error: nil)
    end

    def failure(error)
      OpenStruct.new(success?: false, allocations: [], error: error)
    end
  end
end
