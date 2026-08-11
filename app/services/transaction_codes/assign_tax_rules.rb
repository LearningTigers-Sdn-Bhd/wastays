# frozen_string_literal: true

module TransactionCodes
  # Replaces the set of tax rules carried by a transaction code.
  #
  # The same destroy-and-recreate lived in RoomRevenueController as a private
  # method and again in ApplyHotelTaxRuleChange, and onboarding needed a third
  # copy — so it lives here instead. Callers own `is_taxable`, because the two
  # existing ones set it at different points in their own save sequence.
  #
  # A key names either a primary tax the platform defines ("primary:sst_tax")
  # or one of the hotel's own tax rows ("hotel_tax:12"); TransactionCodeTax
  # builds the same vocabulary in the other direction via #tax_rule_key.
  #
  # Keys are validated against what the hotel actually has, so a stale form or
  # another hotel's tax id fails as an ArgumentError rather than reaching the
  # join table or raising RecordNotFound from deep inside the loop.
  class AssignTaxRules
    def self.call(...) = new(...).call

    def initialize(transaction_code:, keys:)
      @transaction_code = transaction_code
      @hotel = transaction_code.hotel
      @keys = Array(keys).reject(&:blank?).map(&:to_s).uniq
    end

    def call
      unavailable = @keys - available_keys
      raise ArgumentError, "A selected tax rule is unavailable for this hotel." if unavailable.any?

      TransactionCode.transaction do
        @transaction_code.transaction_code_taxes.destroy_all
        @keys.each { |key| create_rule(key) }
      end

      @transaction_code.transaction_code_taxes.reload
      @transaction_code
    end

    def available_keys
      @available_keys ||= TransactionCodeTax::PRIMARY_TAX_KEYS.map { |key| "primary:#{key}" } +
        @hotel.hotel_taxes.pluck(:id).map { |id| "hotel_tax:#{id}" }
    end

    private

    def create_rule(key)
      if key.start_with?("primary:")
        @transaction_code.transaction_code_taxes.create!(primary_tax_key: key.delete_prefix("primary:"))
      else
        tax = @hotel.hotel_taxes.find(key.delete_prefix("hotel_tax:"))
        @transaction_code.transaction_code_taxes.create!(hotel_tax: tax)
      end
    end
  end
end
