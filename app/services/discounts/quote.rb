# frozen_string_literal: true

require "digest"

module Discounts
  class Quote
    Result = ApplicationResult.define(:amount, :calculated_amount, :base_amount, :fingerprint, :metadata)

    def self.call(discount:, folio:, posting_date:, requested_amount: nil, expected_fingerprint: nil, preview: false)
      new(discount:, folio:, posting_date:, requested_amount:, expected_fingerprint:, preview:).call
    end

    def initialize(discount:, folio:, posting_date:, requested_amount:, expected_fingerprint:, preview:)
      @discount = discount
      @folio = folio
      @posting_date = posting_date.to_date
      @requested_amount = requested_amount
      @expected_fingerprint = expected_fingerprint.to_s
      @preview = preview
    end

    def call
      return Result.failure("Discount is not available.") unless available?

      transactions = eligible_transactions
      base_amount = money(transactions.sum(&:amount))
      calculated_amount = calculated_discount(base_amount)
      amount = posting_amount(calculated_amount)
      fingerprint = quote_fingerprint(transactions)
      attributes = result_attributes(transactions, base_amount, calculated_amount, amount, fingerprint)

      return Result.failure("No eligible charges are available for this discount.", **attributes) unless base_amount.positive?
      return Result.failure("Discount amount must be greater than zero.", **attributes) unless @preview || amount&.positive?
      return Result.failure("Discount cannot exceed the eligible charge subtotal.", **attributes) if amount.to_d > base_amount
      if !@preview && (@expected_fingerprint.blank? || @expected_fingerprint != fingerprint)
        return Result.failure("Folio charges changed. Review the updated discount before posting.", **attributes)
      end

      Result.success(**attributes)
    end

    private

    def available?
      @discount.hotel_id == @folio.hotel_id && @discount.active? &&
        @discount.transaction_code.kind == "adjustment" && @discount.transaction_code.category == "discount"
    end

    def eligible_transactions
      scope = @folio.folio_transactions
        .where(transaction_type: "charge", voided_by_transaction_id: nil, reversal_of_transaction_id: nil)
        .where(posting_date: ..@posting_date).where("amount > 0").where.not(category: "tax")
      scope = scope.where(category: "accommodation") if @discount.application_scope == "room_charges"
      if @discount.application_scope == "selected_charges"
        scope = scope.where(transaction_code_id: @discount.applicable_transaction_code_ids)
      end
      scope.includes(:transaction_code).order(:id).to_a
    end

    def calculated_discount(base_amount)
      return nil if @discount.manual?
      return money(@discount.rate_value) if @discount.fixed?

      money(base_amount * @discount.rate_value.to_d / 100)
    end

    def posting_amount(calculated_amount)
      requested = @requested_amount.to_d
      return requested if @discount.manual?
      return requested if @discount.fixed? && @discount.allow_amount_override? && requested.positive?

      calculated_amount
    end

    def quote_fingerprint(transactions)
      parts = [ @discount.id, @discount.updated_at&.utc&.iso8601(6), @discount.pricing_type,
        @discount.rate_value, @discount.application_scope, @posting_date,
        @discount.applicable_transaction_code_ids.sort.join(",") ]
      parts.concat(transactions.map { |transaction| "#{transaction.id}:#{transaction.amount.to_d.to_s('F')}" })
      Digest::SHA256.hexdigest(parts.join("|"))
    end

    def result_attributes(transactions, base_amount, calculated_amount, amount, fingerprint)
      {
        amount:, calculated_amount:, base_amount:, fingerprint:,
        metadata: metadata(transactions, base_amount, calculated_amount, amount)
      }
    end

    def metadata(transactions, base_amount, calculated_amount, amount)
      codes = @discount.applicable_transaction_codes.order(:id)
      {
        hotel_discount_id: @discount.id,
        discount_name: @discount.name,
        discount_code: @discount.code,
        discount_pricing_type: @discount.pricing_type,
        discount_rate_value: @discount.rate_value&.to_d&.to_s("F"),
        discount_application_scope: @discount.application_scope,
        discount_applicable_transaction_code_ids: codes.pluck(:id),
        discount_applicable_transaction_codes: codes.pluck(:code),
        discount_eligible_transaction_ids: transactions.map(&:id),
        discount_eligible_subtotal: base_amount.to_d.to_s("F"),
        discount_calculated_amount: calculated_amount&.to_d&.to_s("F"),
        discount_posted_amount: amount&.to_d&.to_s("F"),
        discount_amount_override: calculated_amount.present? && amount.to_d != calculated_amount.to_d
      }.compact
    end

    def money(value)
      value.to_d.round(2)
    end
  end
end
