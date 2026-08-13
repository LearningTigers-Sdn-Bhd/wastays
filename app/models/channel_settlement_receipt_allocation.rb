# frozen_string_literal: true

class ChannelSettlementReceiptAllocation < ApplicationRecord
  belongs_to :channel_settlement_receipt
  belongs_to :channel_settlement_allocation

  validates :currency, presence: true, inclusion: { in: ->(_) { CurrencyCatalog.codes } }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :channel_settlement_allocation_id, uniqueness: { scope: :channel_settlement_receipt_id }
  validate :references_share_tenant_and_source
  validate :currency_matches_references

  private

  def references_share_tenant_and_source
    return if channel_settlement_receipt.blank? || channel_settlement_allocation.blank?

    settlement = channel_settlement_allocation.channel_settlement
    if settlement.hotel_id != channel_settlement_receipt.hotel_id
      errors.add(:channel_settlement_allocation, "must belong to the receipt hotel")
    end
    if settlement.booking_source_id != channel_settlement_receipt.booking_source_id
      errors.add(:channel_settlement_allocation, "must use the receipt booking source")
    end
  end

  def currency_matches_references
    return if currency.blank?

    receipt = channel_settlement_receipt
    allocation = channel_settlement_allocation
    if receipt.present? && receipt.currency != currency
      errors.add(:currency, "must match the receipt currency")
    end
    if allocation.present? && allocation.currency != currency
      errors.add(:currency, "must match the settlement allocation currency")
    end
  end
end
