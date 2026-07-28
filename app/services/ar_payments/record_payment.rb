# frozen_string_literal: true

require "ostruct"

module ArPayments
  class RecordPayment
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(hotel:, hotel_corporate_account:, user:, amount:, currency:, reference_number:, received_at:, payment_method:, notes: nil, allocations: {}, metadata: {})
      @hotel = hotel
      @hotel_corporate_account = hotel_corporate_account
      @user = user
      @amount = amount.to_d
      @currency = currency.to_s
      @reference_number = reference_number.to_s.strip
      @received_at = received_at
      @payment_method = payment_method.to_s
      @notes = notes.to_s.strip.presence
      @allocations = allocations
      @metadata = metadata || {}
    end

    def call
      error = validate_payment_inputs
      return failure(error) if error.present?

      payment = nil
      ActiveRecord::Base.transaction do
        invoices.each(&:lock!)
        allocation_error = validate_allocations
        raise ActiveRecord::Rollback, allocation_error if allocation_error.present?

        payment = ArPayment.create!(payment_attributes)
        allocation_rows.each do |row|
          invoice = invoices_by_id.fetch(row[:invoice_id])
          payment.ar_payment_allocations.create!(ar_invoice: invoice, amount: row[:amount], metadata: allocation_metadata(invoice))
          update_invoice!(invoice, row[:amount])
        end
        record_audit_event!(payment)
      rescue ActiveRecord::Rollback => e
        return failure(e.message)
      end

      auto_allocate!(payment) if allocation_rows.empty? && @hotel_corporate_account.auto_allocate_payments?

      success(payment)
    rescue ActiveRecord::RecordInvalid => e
      failure(e.record.errors.full_messages.to_sentence)
    rescue StandardError => e
      failure(e.message)
    end

    private

    def payment_attributes
      {
        hotel: @hotel,
        hotel_corporate_account: @hotel_corporate_account,
        amount: @amount,
        currency: @currency,
        reference_number: @reference_number,
        received_at: @received_at,
        payment_method: @payment_method,
        notes: @notes,
        metadata: @metadata.deep_stringify_keys
      }
    end

    def validate_payment_inputs
      return "Corporate Account must belong to the hotel." if @hotel_corporate_account.blank? || @hotel_corporate_account.hotel_id != @hotel.id
      return "Payment amount must be greater than zero." unless @amount.positive?
      return "Payment reference number can't be blank." if @reference_number.blank?
      return "Received date can't be blank." if @received_at.blank?
      "Payment method is not supported." unless @payment_method.in?(ArPayment::PAYMENT_METHODS)
    end

    def validate_allocations
      return "Allocation total cannot exceed payment amount." if allocation_total > @amount

      allocation_rows.each do |row|
        invoice = invoices_by_id[row[:invoice_id]]
        return "Invoice #{row[:invoice_id]} is not available for this corporate account." if invoice.blank?
        return "Allocation amount must be greater than zero." unless row[:amount].positive?
        return "Allocation for #{invoice.formatted_invoice_number} exceeds outstanding amount." if row[:amount] > invoice.outstanding_amount.to_d
        return "Cannot allocate payment to void invoice #{invoice.formatted_invoice_number}." if invoice.void?
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
      @invoices ||= @hotel.receivables.where(id: allocation_rows.map { |row| row[:invoice_id] }).to_a
    end

    def invoices_by_id
      @invoices_by_id ||= invoices.index_by(&:id)
    end

    def update_invoice!(invoice, allocation_amount)
      paid_amount = invoice.paid_amount.to_d + allocation_amount
      outstanding_amount = invoice.outstanding_amount.to_d - allocation_amount
      invoice.update!(
        paid_amount: paid_amount,
        outstanding_amount: outstanding_amount,
        status: invoice_status(paid_amount, outstanding_amount)
      )
    end

    def invoice_status(paid_amount, outstanding_amount)
      return "paid" if outstanding_amount.zero?
      return "partially_paid" if paid_amount.positive?

      "open"
    end

    def allocation_metadata(invoice)
      {
        ar_invoice_id: invoice.id,
        invoice_number: invoice.invoice_number,
        reference_number: @reference_number,
        received_at: @received_at.to_s
      }
    end

    def record_audit_event!(payment)
      FinancialControls::AuditEventRecorder.call!(
        hotel: @hotel,
        business_date: @hotel.current_business_date,
        event_type: "ar_payment_recorded",
        source: "ar_payments",
        actor: @user,
        amount: payment.amount,
        currency: payment.currency,
        metadata: {
          ar_payment_id: payment.id,
          reference_number: payment.reference_number,
          received_at: payment.received_at.iso8601,
          hotel_corporate_account_id: payment.hotel_corporate_account_id,
          corporate_account_id: payment.hotel_corporate_account.corporate_account_id,
          allocations: payment.ar_payment_allocations.map do |allocation|
            {
              ar_invoice_id: allocation.ar_invoice_id,
              invoice_number: allocation.ar_invoice.invoice_number,
              amount: allocation.amount.to_s("F")
            }
          end
        }
      )
    end

    def auto_allocate!(payment)
      ArPayments::AutoAllocate.call(payment: payment, user: @user)
    end

    def success(payment)
      OpenStruct.new(success?: true, ar_payment: payment)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error, ar_payment: nil)
    end
  end
end
