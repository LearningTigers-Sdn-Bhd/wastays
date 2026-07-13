# frozen_string_literal: true

module FolioRouting
  class EffectiveTaxRules
    def self.call(booking:, transaction_code:)
      defaults = transaction_code.transaction_code_taxes.includes(:hotel_tax).index_by(&:tax_rule_key)
      overrides = booking.booking_tax_inclusion_overrides.where(transaction_code: transaction_code).includes(:hotel_tax).index_by(&:tax_key)

      overrides.each_value do |override|
        if override.action == "exclude"
          defaults.delete(override.tax_key)
        else
          defaults[override.tax_key] ||= TransactionCodeTax.new(
            transaction_code: transaction_code,
            hotel_tax: override.hotel_tax,
            primary_tax_key: override.primary_tax_key
          )
        end
      end
      defaults.values
    end
  end
end
