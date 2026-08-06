# frozen_string_literal: true

module Folios
  module Payments
    class PostConfiguredPayment
      def self.call(folio:, user:, payment_method_id:, base_amount:, description:, posting_date: nil, options: {})
        new(
          folio:, user:, payment_method_id:, base_amount:, description:, posting_date:, options:
        ).call
      end

      def initialize(folio:, user:, payment_method_id:, base_amount:, description:, posting_date:, options:)
        @folio = folio
        @user = user
        @payment_method_id = payment_method_id
        @base_amount = base_amount.to_d
        @description = description
        @posting_date = posting_date
        @options = options
      end

      def call
        return failure("Amount must be greater than zero.") unless @base_amount.positive?

        @payment_method = @folio.hotel.hotel_payment_methods
          .active
          .includes(:transaction_code, surcharge_extra_charge: { transaction_code: :transaction_code_taxes })
          .find_by(id: @payment_method_id)
        return failure("Payment method is not valid.") if @payment_method.blank?

        operation_key = @options[:operation_key].presence || SecureRandom.uuid
        surcharge_amount = @payment_method.surcharge_amount(@base_amount)
        charge_result = nil
        payment_result = nil

        ActiveRecord::Base.transaction do
          if surcharge_amount.positive?
            charge_result = post_surcharge(surcharge_amount, operation_key)
            unless charge_result.success?
              payment_result = failure(charge_result.error)
              raise ActiveRecord::Rollback
            end
          end

          tax_total = Array(charge_result&.tax_transactions).sum { |transaction| transaction.amount.to_d }
          collected_total = (@base_amount + surcharge_amount + tax_total).round(2)
          payment_result = post_payment(collected_total, surcharge_amount, tax_total, operation_key)
          raise ActiveRecord::Rollback unless payment_result.success?

          transactions = [ charge_result&.transaction, *Array(charge_result&.tax_transactions), payment_result.transaction ].compact
          payment_result = Folios::Transactions::TransactionResult.success(
            transaction: payment_result.transaction,
            transactions: transactions,
            tax_transactions: Array(charge_result&.tax_transactions)
          )
        end

        payment_result || failure("Payment could not be posted.")
      end

      private

      def post_surcharge(amount, operation_key)
        extra_charge = @payment_method.surcharge_extra_charge
        return failure("Payment surcharge is not available.") if extra_charge.blank? || !extra_charge.active?

        Folios::Transactions::PostStaffTransaction.call(
          folio: @folio,
          user: @user,
          transaction_type: "charge",
          category: extra_charge.category,
          transaction_code_id: extra_charge.transaction_code_id,
          amount: amount,
          description: "#{@payment_method.name} surcharge fee",
          posting_date: @posting_date,
          options: @options.merge(
            require_transaction_code: true,
            operation_key: operation_key,
            system_generated_payment_surcharge: true,
            metadata: shared_metadata(amount).merge(
              posting_source: "payment_surcharge",
              hotel_extra_charge_id: extra_charge.id
            )
          )
        )
      end

      def post_payment(collected_total, surcharge_amount, surcharge_tax_total, operation_key)
        Folios::Transactions::PostStaffTransaction.call(
          folio: @folio,
          user: @user,
          transaction_type: "payment",
          category: @payment_method.transaction_code.category,
          amount: collected_total,
          description: @description,
          posting_date: @posting_date,
          options: @options.merge(
            hotel_payment_method_id: @payment_method.id,
            operation_key: operation_key,
            metadata: (@options[:metadata] || {}).merge(
              hotel_payment_method_id: @payment_method.id,
              payment_base_amount: @base_amount.to_s("F"),
              payment_surcharge_amount: surcharge_amount.to_s("F"),
              payment_surcharge_tax_amount: surcharge_tax_total.to_d.to_s("F"),
              payment_collected_total: collected_total.to_s("F"),
              payment_operation_key: operation_key
            )
          )
        )
      end

      def shared_metadata(amount)
        (@options[:metadata] || {}).merge(
          hotel_payment_method_id: @payment_method.id,
          payment_method_name: @payment_method.name,
          payment_base_amount: @base_amount.to_s("F"),
          payment_surcharge_posting_type: @payment_method.surcharge_posting_type,
          payment_surcharge_value: @payment_method.surcharge_value.to_d.to_s("F"),
          payment_surcharge_amount: amount.to_s("F")
        )
      end

      def failure(error)
        Folios::Transactions::TransactionResult.failure(error)
      end
    end
  end
end
