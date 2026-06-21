# frozen_string_literal: true

require "ostruct"

module Folios
  class PostStaffTransaction
    ALLOWED_CATEGORIES = {
      "charge" => %w[other],
      "payment" => %w[cash booking_payment gateway_payment refund],
      "adjustment" => %w[adjustment correction discount write_off other]
    }.freeze

    def self.call(folio:, user:, transaction_type:, category:, amount:, description:, posting_date: nil, transaction_code_id: nil, options: {})
      new(
        folio: folio,
        user: user,
        transaction_type: transaction_type,
        category: category,
        amount: amount,
        description: description,
        posting_date: posting_date,
        transaction_code_id: transaction_code_id,
        options: options
      ).call
    end

    def initialize(folio:, user:, transaction_type:, category:, amount:, description:, posting_date: nil, transaction_code_id: nil, options: {})
      @folio = folio
      @user = user
      @transaction_type = transaction_type.to_s
      @category = category.to_s
      @amount = amount.to_d
      @description = description.to_s.strip
      @posting_date = posting_date.presence || @folio.hotel.current_business_date
      @transaction_code_id = transaction_code_id.presence
      @options = options
      @require_transaction_code = !!@options[:require_transaction_code]
      @payment_source = nil
    end

    def call
      payment_source_error = apply_payment_source
      return failure(payment_source_error) if payment_source_error.present?

      refund_source_error = validate_refund_source
      return failure(refund_source_error) if refund_source_error.present?

      code_error = apply_transaction_code
      return failure(code_error) if code_error.present?

      return failure("Transaction type is not allowed.") unless allowed_transaction_type?
      return failure("Category is not allowed for #{@transaction_type} transactions.") unless allowed_category?
      return failure("Description can't be blank.") if @description.blank?
      return failure("Amount must be greater than zero.") if requires_positive_amount? && !@amount.positive?
      return failure("Amount can't be zero.") if @transaction_type == "adjustment" && @amount.zero?

      result = nil
      ActiveRecord::Base.transaction do
        result = Folios::InsertTransaction.new(
          booking_folio: @folio,
          amount: normalized_amount,
          transaction_type: @transaction_type,
          category: @category,
          user: @user,
          description: @description,
          posting_date: @posting_date,
          options: @options.merge(
            metadata: staff_metadata.merge(
              posting_source: @options[:posting_source].presence || "staff",
              posted_from: "booking_show",
              posted_by_user_id: @user&.id
            )
          ).merge(transaction_code: @transaction_code)
        ).call

        next unless result.success? && taxable_charge?

        tax_results = post_tax_transactions(result.transaction)
        failed_tax = tax_results.find { |tax_result| !tax_result.success? }
        if failed_tax
          result = failure(failed_tax.error)
          raise ActiveRecord::Rollback
        end

        result.tax_transactions = tax_results.map(&:transaction).compact
      end

      result
    end

    private

    def apply_payment_source
      return unless staff_payment?

      source_key = @options[:payment_source].to_s
      return "Payment source is required." if source_key.blank?

      @payment_source = Folios::PaymentSource.fetch(source_key)
      return "Payment source is not valid." if @payment_source.blank?

      reference = payment_source_reference
      return "#{@payment_source.label} reference is required." if @payment_source.required_reference? && reference.blank?

      @transaction_code = @payment_source.transaction_code_for(@folio.hotel)
      return "Payment transaction code is not available." if @transaction_code.blank? || !@transaction_code.active?
      return "Payment transaction code must be a payment code." unless @transaction_code.kind == "payment"

      @transaction_type = @transaction_code.kind
      @category = @transaction_code.category
      @transaction_code_id = nil
      nil
    end

    def apply_transaction_code
      return "Transaction code is required for manual charges." if @require_transaction_code && @transaction_code_id.blank?
      return if @transaction_code_id.blank?

      @transaction_code = @folio.hotel.transaction_codes.find_by(id: @transaction_code_id)
      return "Transaction code is not available." if @transaction_code.blank? || !@transaction_code.active?
      return "Transaction code must be a charge code." if @require_transaction_code && @transaction_code.kind != "charge"

      @transaction_type = @transaction_code.kind
      @category = @transaction_code.category
      nil
    end

    def allowed_transaction_type?
      ALLOWED_CATEGORIES.key?(@transaction_type)
    end

    def allowed_category?
      return true if @transaction_code.present? && @transaction_type == "charge" && @category.in?(FolioTransaction::CHARGE_CATEGORIES)

      @category.in?(ALLOWED_CATEGORIES.fetch(@transaction_type, []))
    end

    def staff_payment?
      @transaction_type == "payment" && @category != "refund"
    end

    def refund_payment?
      @transaction_type == "payment" && @category == "refund"
    end

    def validate_refund_source
      return unless refund_payment?

      source_key = @options.dig(:metadata, :refund_source).presence || @options.dig(:metadata, "refund_source").presence
      return "Refund source is required." if source_key.blank?
      return "Refund source is not valid." unless Folios::RefundSource.valid?(source_key)

      nil
    end

    def payment_source_reference
      return if @payment_source.blank?

      @options.dig(:payment_references, @payment_source.reference_key).presence ||
        @options.dig(:payment_references, @payment_source.reference_key.to_sym).presence ||
        @options.dig(:metadata, @payment_source.reference_key).presence ||
        @options.dig(:metadata, @payment_source.reference_key.to_sym).presence ||
        @options.dig(:metadata, :reference).presence ||
        @options.dig(:metadata, "reference").presence
    end

    def staff_metadata
      metadata = (@options[:metadata] || {}).dup
      return metadata if @payment_source.blank?

      reference = payment_source_reference.to_s.strip
      metadata[:payment_source] = @payment_source.key
      metadata[:reference] = reference if reference.present? && metadata[:reference].blank? && metadata["reference"].blank?
      metadata[:source_references] = source_references_metadata(metadata, reference) if reference.present?
      metadata[:manual_recovery] = true if @payment_source.manual_recovery?
      metadata
    end

    def source_references_metadata(metadata, reference)
      metadata.fetch(:source_references, metadata.fetch("source_references", {})).to_h.merge(
        @payment_source.reference_key => reference
      )
    end

    def normalized_amount
      return -@amount.abs if @transaction_type == "payment" && @category == "refund"

      @amount
    end

    def requires_positive_amount?
      @transaction_type == "charge" || @transaction_type == "payment"
    end

    def taxable_charge?
      @transaction_type == "charge" && @transaction_code&.is_taxable? && active_tax_rules.any?
    end

    def post_tax_transactions(parent_transaction)
      active_tax_rules.map do |tax_rule|
        amount = tax_rule.compute(@amount.abs).to_d
        next if amount.zero?

        Folios::InsertTransaction.new(
          booking_folio: @folio,
          amount: amount,
          transaction_type: "charge",
          category: "tax",
          user: @user,
          description: "Tax: #{tax_rule.display_name} for #{parent_transaction.description}",
          posting_date: @posting_date,
          options: @options.merge(
            posting_source: @options[:posting_source].presence || "staff",
            transaction_code: tax_rule.posting_transaction_code,
            metadata: (@options[:metadata] || {}).merge(
              posting_source: @options[:posting_source].presence || "staff",
              posted_from: "booking_show",
              posted_by_user_id: @user&.id,
              parent_folio_transaction_id: parent_transaction.id,
              source_transaction_code_id: @transaction_code.id,
              tax_line: tax_line(tax_rule, amount)
            )
          )
        ).call
      end.compact
    end

    def active_tax_rules
      @active_tax_rules ||= @transaction_code.transaction_code_taxes.includes(:hotel_tax).select(&:enabled_for_posting?)
    end

    def tax_line(tax_rule, amount)
      posting_transaction_code = tax_rule.posting_transaction_code
      {
        tax_id: tax_rule.hotel_tax_id,
        primary_tax_key: tax_rule.primary_tax_key,
        name: tax_rule.display_name,
        type: tax_rule.tax_line_type,
        transaction_code_id: posting_transaction_code&.id,
        transaction_code_code: posting_transaction_code&.code,
        rate_type: tax_rule.rate_type,
        rate: tax_rule.amount.to_d.to_s("F"),
        basis: "staff_charge",
        basis_amount: @amount.abs.to_s("F"),
        amount: amount.to_s("F"),
        source: "transaction_code_tax_rule"
      }
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error)
    end
  end
end
