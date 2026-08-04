# frozen_string_literal: true

module Folios
  module Payments
    class PostConfiguredSurcharge
      Result = ApplicationResult.define(:transactions, :tax_transactions, :surcharge_amount, :surcharge_tax_total)

      def self.call(folio:, payment_method:, base_amount:, user:, posting_date: nil, operation_key:, metadata: {},
        override_night_audit: false, override_reason: nil)
        new(
          folio:, payment_method:, base_amount:, user:, posting_date:, operation_key:, metadata:,
          override_night_audit:, override_reason:
        ).call
      end

      def initialize(folio:, payment_method:, base_amount:, user:, posting_date:, operation_key:, metadata:,
        override_night_audit:, override_reason:)
        @folio = folio
        @payment_method = payment_method
        @base_amount = base_amount.to_d.round(2)
        @user = user
        @posting_date = posting_date
        @operation_key = operation_key
        @metadata = metadata.to_h
        @override_night_audit = override_night_audit
        @override_reason = override_reason
      end

      def call
        surcharge_amount = @payment_method.surcharge_amount(@base_amount)
        return success([], [], surcharge_amount, 0.to_d) unless surcharge_amount.positive?

        extra_charge = @payment_method.surcharge_extra_charge
        return failure("Payment surcharge is not available.") if extra_charge.blank? || !extra_charge.active?

        result = Folios::Transactions::PostStaffTransaction.call(
          folio: @folio,
          user: @user,
          transaction_type: "charge",
          category: extra_charge.category,
          transaction_code_id: extra_charge.transaction_code_id,
          amount: surcharge_amount,
          description: "#{@payment_method.name} surcharge fee",
          posting_date: @posting_date,
          options: posting_options.merge(
            require_transaction_code: true,
            operation_key: @operation_key,
            system_generated_payment_surcharge: true,
            metadata: @metadata.merge(
              posting_source: "payment_surcharge",
              hotel_extra_charge_id: extra_charge.id,
              hotel_payment_method_id: @payment_method.id,
              payment_method_name: @payment_method.name,
              payment_method_code: @payment_method.code,
              payment_surcharge_amount: surcharge_amount.to_s("F")
            )
          )
        )
        return failure(result.error) unless result.success?

        tax_transactions = Array(result.tax_transactions)
        success([ result.transaction, *tax_transactions ], tax_transactions, surcharge_amount,
          tax_transactions.sum { |transaction| transaction.amount.to_d }.round(2))
      end

      private

      def posting_options
        options = { posting_source: "payment_surcharge" }
        return options unless @override_night_audit

        options.merge(
          override_night_audit: true,
          correction_reason: "payment_surcharge_on_retroactive_booking",
          correction_note: @override_reason.to_s.presence || "Payment surcharge posted for a backdated booking."
        )
      end

      def success(transactions, tax_transactions, surcharge_amount, tax_total)
        Result.success(
          transactions:, tax_transactions:, surcharge_amount:, surcharge_tax_total: tax_total
        )
      end

      def failure(message)
        Result.failure(message, transactions: [], tax_transactions: [], surcharge_amount: 0.to_d, surcharge_tax_total: 0.to_d)
      end
    end
  end
end
