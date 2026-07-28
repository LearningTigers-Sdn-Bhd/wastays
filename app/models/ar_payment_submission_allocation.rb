# frozen_string_literal: true

class ArPaymentSubmissionAllocation < ApplicationRecord
  belongs_to :ar_payment_submission
  belongs_to :ar_invoice
  belongs_to :receivable, class_name: "Receivable", foreign_key: :ar_invoice_id

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :ar_invoice_id, uniqueness: { scope: :ar_payment_submission_id }
  validate :ar_invoice_matches_submission_hotel_corporate_account
  validate :amount_does_not_exceed_invoice_outstanding

  private

  def ar_invoice_matches_submission_hotel_corporate_account
    return if ar_invoice.blank? || ar_payment_submission.blank?
    return if ar_invoice.hotel_corporate_account_id == ar_payment_submission.hotel_corporate_account_id

    errors.add(:ar_invoice, "must belong to the same corporate account")
  end

  def amount_does_not_exceed_invoice_outstanding
    return if ar_invoice.blank? || amount.blank?
    return if amount.to_d <= ar_invoice.outstanding_amount.to_d

    errors.add(:amount, "cannot exceed the invoice's outstanding balance")
  end
end
