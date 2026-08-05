# frozen_string_literal: true


module Folios
  module Charges
    # Posts a stay-event charge — late checkout, early departure, cancellation.
    #
    # These bill a room night, so they carry ROOM's tax rules even though they post
    # under their own code for GL and reporting. Before this, the charge went
    # straight to InsertTransaction with no transaction code at all, which meant no
    # tax was ever attached: tax lines are only posted when a code is present.
    class PostCategoryCharge
      ALLOWED_CATEGORIES = %w[late_checkout_charge early_departure_charge cancellation_charge].freeze

      def self.call(folio:, user:, category:, amount:, description: nil, metadata: {}, options: {})
        new(folio: folio, user: user, category: category, amount: amount, description: description, metadata: metadata, options: options).call
      end

      def initialize(folio:, user:, category:, amount:, description: nil, metadata: {}, options: {})
        @folio = folio
        @user = user
        @category = category.to_s
        @amount = amount.to_d
        @description = description.presence || default_description
        @metadata = metadata
        @options = options
      end

      def call
        return failure("Invalid charge category: #{@category}") unless ALLOWED_CATEGORIES.include?(@category)
        return failure("Charge amount must be greater than zero") unless @amount.positive?
        return failure("No transaction code is configured for #{@category.titleize}.") if transaction_code.blank?

        result = nil
        ActiveRecord::Base.transaction do
          result = insert_charge
          next unless result.success?

          tax_result = post_attached_taxes(result.transaction)
          unless tax_result.success?
            result = failure(tax_result.error)
            raise ActiveRecord::Rollback
          end

          next if tax_result.tax_transactions.empty?

          result = result.with(tax_transactions: tax_result.tax_transactions)
        end

        result
      end

      private

      def insert_charge
        Folios::Transactions::InsertTransaction.new(
          booking_folio: @folio,
          amount: @amount,
          transaction_type: "charge",
          category: @category,
          user: @user,
          description: @description,
          posting_date: posting_date,
          options: charge_options
        ).call
      end

      def post_attached_taxes(parent_transaction)
        Folios::Transactions::PostAttachedTaxes.call(
          folio: @folio,
          parent_transaction: parent_transaction,
          source_transaction_code: transaction_code,
          tax_rule_transaction_code: tax_rule_transaction_code,
          base_amount: @amount,
          posting_date: posting_date,
          user: @user,
          basis: @category,
          options: charge_options
        )
      end

      # A backdated or closed-date posting still has to land, so it goes through as a
      # system correction. The tax lines inherit the same treatment — they post to the
      # same date as the charge they belong to, and would otherwise be refused.
      def charge_options
        @charge_options ||= begin
          options = @options.merge(
            transaction_code: transaction_code,
            metadata: @metadata.merge(posting_source: "charge_service", charge_type: @category)
          )

          if @folio.hotel.date_closed?(posting_date) || posting_date < @folio.hotel.current_business_date
            options[:override_night_audit] = true
            options[:system_posting] = true
            options[:correction_reason] ||= "charge_on_closed_date"
            options[:correction_note] ||= "Automated posting of #{@category.titleize} on a closed business date."
          end

          options
        end
      end

      def posting_date
        @posting_date ||= @options[:posting_date] || @folio.hotel.current_business_date
      end

      def transaction_code
        return @transaction_code if defined?(@transaction_code)

        @transaction_code = transaction_code_resolver.for_key(
          Financials::EnsureDefaultTransactionCodes.system_key_for_category(@category)
        )
      end

      def tax_rule_transaction_code
        @tax_rule_transaction_code ||= transaction_code_resolver.tax_rule_source_for(transaction_code)
      end

      def transaction_code_resolver
        @transaction_code_resolver ||= TransactionCodes::Resolver.for(@folio.hotel)
      end

      def default_description
        @category.titleize
      end

      def failure(error)
        Folios::Transactions::TransactionResult.failure(error)
      end
    end
  end
end
