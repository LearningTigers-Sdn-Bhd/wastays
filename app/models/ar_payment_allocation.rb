# frozen_string_literal: true

class ArPaymentAllocation < ApplicationRecord
  belongs_to :ar_payment
  belongs_to :ar_invoice

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :ar_invoice_id, uniqueness: { scope: :ar_payment_id }
  validates :metadata, exclusion: { in: [ nil ] }
  validate :references_match_payment

  private

  def references_match_payment
    return if ar_payment.blank? || ar_invoice.blank?

    errors.add(:ar_invoice, "must belong to the payment hotel") unless ar_invoice.hotel_id == ar_payment.hotel_id
    errors.add(:ar_invoice, "must belong to the payment corporate account") unless ar_invoice.hotel_corporate_account_id == ar_payment.hotel_corporate_account_id
    errors.add(:ar_invoice, "must use the payment currency") unless ar_invoice.currency == ar_payment.currency
  end
end
