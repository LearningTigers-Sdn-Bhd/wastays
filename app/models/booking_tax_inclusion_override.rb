# frozen_string_literal: true

class BookingTaxInclusionOverride < ApplicationRecord
  ACTIONS = %w[include exclude].freeze

  belongs_to :hotel
  belongs_to :booking
  belongs_to :transaction_code
  belongs_to :hotel_tax, optional: true
  belongs_to :actor, class_name: "User", optional: true

  validates :action, inclusion: { in: ACTIONS }
  validates :primary_tax_key, inclusion: { in: TransactionCodeTax::PRIMARY_TAX_KEYS }, allow_blank: true
  validate :exactly_one_tax_source
  validate :records_share_hotel

  def tax_key
    primary_tax_key.present? ? "primary:#{primary_tax_key}" : "hotel_tax:#{hotel_tax_id}"
  end

  private

  def exactly_one_tax_source
    errors.add(:base, "must reference exactly one tax") unless hotel_tax_id.present? ^ primary_tax_key.present?
  end

  def records_share_hotel
    errors.add(:booking, "must belong to hotel") if booking && booking.hotel_id != hotel_id
    errors.add(:transaction_code, "must belong to hotel") if transaction_code && transaction_code.hotel_id != hotel_id
    errors.add(:hotel_tax, "must belong to hotel") if hotel_tax && hotel_tax.hotel_id != hotel_id
  end
end
