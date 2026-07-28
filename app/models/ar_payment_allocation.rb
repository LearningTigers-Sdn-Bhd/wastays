# frozen_string_literal: true

class ArPaymentAllocation < ApplicationRecord
  belongs_to :ar_payment
  belongs_to :ar_invoice, class_name: "Receivable", foreign_key: :ar_invoice_id
  has_one :reversal, class_name: "ArPaymentAllocationReversal", dependent: :restrict_with_error

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :metadata, exclusion: { in: [ nil ] }
  validate :references_match_payment

  scope :active, -> { left_joins(:reversal).where(ar_payment_allocation_reversals: { id: nil }) }

  def reversed?
    reversal.present?
  end

  before_update :prevent_update
  before_destroy :prevent_destroy

  private

  def prevent_update
    errors.add(:base, "AR payment allocations are immutable.")
    throw :abort
  end

  def prevent_destroy
    errors.add(:base, "AR payment allocations are immutable and cannot be deleted.")
    throw :abort
  end

  def references_match_payment
    return if ar_payment.blank? || ar_invoice.blank?

    errors.add(:ar_invoice, "must belong to the payment hotel") unless ar_invoice.hotel_id == ar_payment.hotel_id
    errors.add(:ar_invoice, "must belong to the payment corporate account") unless ar_invoice.hotel_corporate_account_id == ar_payment.hotel_corporate_account_id
    errors.add(:ar_invoice, "must use the payment currency") unless ar_invoice.currency == ar_payment.currency
  end
end
