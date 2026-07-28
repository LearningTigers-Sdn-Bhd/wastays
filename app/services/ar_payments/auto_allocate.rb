# frozen_string_literal: true

require "ostruct"

module ArPayments
  # Applies a payment's unallocated balance to its corporate account's open
  # invoices oldest-due-first (FIFO), leaving any remainder unapplied as
  # credit. Delegates the actual allocation/validation to AllocatePayment so
  # both paths share the same locking and invariants.
  class AutoAllocate
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(payment:, user:)
      @payment = payment
      @user = user
    end

    def call
      return success([]) if allocation_rows.empty?

      ArPayments::AllocatePayment.call(payment: @payment, user: @user, allocations: allocation_rows)
    end

    private

    def allocation_rows
      @allocation_rows ||= begin
        remaining = @payment.unallocated_amount
        rows = {}

        open_invoices.each do |invoice|
          break unless remaining.positive?

          amount = [ remaining, invoice.outstanding_amount.to_d ].min
          next unless amount.positive?

          rows[invoice.id] = amount
          remaining -= amount
        end

        rows
      end
    end

    def open_invoices
      @payment.hotel.receivables
        .with_open_balance
        .where(hotel_corporate_account: @payment.hotel_corporate_account, currency: @payment.currency)
        .order(due_on: :asc, invoice_number: :asc)
    end

    def success(allocations)
      OpenStruct.new(success?: true, allocations: allocations, error: nil)
    end
  end
end
