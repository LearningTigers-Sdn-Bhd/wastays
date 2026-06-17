# frozen_string_literal: true

class TransactionCodeTax < ApplicationRecord
  PRIMARY_TAX_KEYS = %w[sst_tax tourism_tax].freeze

  belongs_to :transaction_code
  belongs_to :hotel_tax, optional: true

  validates :primary_tax_key, inclusion: { in: PRIMARY_TAX_KEYS }, allow_blank: true
  validate :exactly_one_tax_source
  validate :hotel_tax_belongs_to_same_hotel

  def tax_rule_key
    primary_tax_key.present? ? "primary:#{primary_tax_key}" : "hotel_tax:#{hotel_tax_id}"
  end

  def primary_tax?
    primary_tax_key.present?
  end

  def display_name
    return hotel_tax.name if hotel_tax.present?

    primary_tax_key == "sst_tax" ? "SST 8%" : "Tourism Tax"
  end

  def rate_type
    return hotel_tax.rate_type if hotel_tax.present?

    primary_tax_key == "sst_tax" ? "percentage" : "flat"
  end

  def amount
    return hotel_tax.amount.to_d if hotel_tax.present?
    return 8.to_d if primary_tax_key == "sst_tax"

    transaction_code.hotel.tourism_tax_amount.to_d
  end

  def enabled_for_posting?
    return hotel_tax.enabled? if hotel_tax.present?
    return transaction_code.hotel.sst_enabled? if primary_tax_key == "sst_tax"

    transaction_code.hotel.tourism_tax_enabled?
  end

  def compute(basis_amount)
    rate_type == "percentage" ? (basis_amount.to_d * amount / 100).round(2) : amount
  end

  def posting_transaction_code
    return hotel_tax.ensure_transaction_code if hotel_tax.present?

    Financials::EnsureDefaultTransactionCodes.call(transaction_code.hotel)
    transaction_code.hotel.transaction_codes.find_by(system_key: primary_tax_key)
  end

  def tax_line_type
    return "custom" if hotel_tax.present?

    primary_tax_key == "sst_tax" ? "sst" : "tourism_tax"
  end

  private

  def exactly_one_tax_source
    return if hotel_tax_id.present? ^ primary_tax_key.present?

    errors.add(:base, "must reference either a hotel tax or a primary tax")
  end

  def hotel_tax_belongs_to_same_hotel
    return if transaction_code.blank? || hotel_tax.blank?
    return if transaction_code.hotel_id == hotel_tax.hotel_id

    errors.add(:hotel_tax, "must belong to the same hotel as the transaction code")
  end
end
