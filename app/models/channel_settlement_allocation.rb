# frozen_string_literal: true

class ChannelSettlementAllocation < ApplicationRecord
  belongs_to :channel_settlement
  belongs_to :booking
  belongs_to :booking_folio
  has_many :channel_settlement_receipt_allocations, dependent: :restrict_with_error
  has_many :channel_settlement_receipts, through: :channel_settlement_receipt_allocations

  validates :currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :gross_amount, :expected_net_amount, presence: true,
    numericality: { greater_than_or_equal_to: 0 }
  validates :commission_amount, presence: true,
    numericality: { greater_than_or_equal_to: 0 }
  validates :booking_id, uniqueness: { scope: :channel_settlement_id }
  validate :booking_belongs_to_settlement_hotel
  validate :folio_belongs_to_booking_and_settlement_hotel
  validate :folio_is_ota_identity
  validate :currency_matches_settlement
  validate :commission_does_not_exceed_gross_amount
  validate :expected_net_matches_components

  private

  def booking_belongs_to_settlement_hotel
    return if channel_settlement.blank? || booking.blank?
    return if booking.hotel_id == channel_settlement.hotel_id

    errors.add(:booking, "must belong to the settlement hotel")
  end

  def folio_belongs_to_booking_and_settlement_hotel
    return if booking_folio.blank?

    if booking.present? && booking_folio.booking_id != booking_id
      errors.add(:booking_folio, "must belong to the allocated booking")
    end
    if channel_settlement.present? && booking_folio.hotel_id != channel_settlement.hotel_id
      errors.add(:booking_folio, "must belong to the settlement hotel")
    end
  end

  def folio_is_ota_identity
    return if booking_folio.blank?
    return if booking_folio.payer_type == "ota" && booking_folio.booking_billing_party&.party_kind == "ota"

    errors.add(:booking_folio, "must be an OTA payer folio")
  end

  def currency_matches_settlement
    return if channel_settlement.blank? || currency.blank?
    return if channel_settlement.currency == currency

    errors.add(:currency, "must match the settlement currency")
  end

  def commission_does_not_exceed_gross_amount
    return if gross_amount.blank? || commission_amount.blank?
    return unless commission_amount.to_d > gross_amount.to_d

    errors.add(:commission_amount, "must not exceed gross amount")
  end

  def expected_net_matches_components
    return if gross_amount.blank? || commission_amount.blank? || expected_net_amount.blank?
    return if expected_net_amount.to_d == (gross_amount.to_d - commission_amount.to_d)

    errors.add(:expected_net_amount, "must equal gross amount minus commission amount")
  end
end
