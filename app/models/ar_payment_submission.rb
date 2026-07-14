# frozen_string_literal: true

class ArPaymentSubmission < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :hotel
  belongs_to :hotel_corporate_account
  belongs_to :submitted_by, class_name: "User"
  belongs_to :ar_payment, optional: true
  belongs_to :ar_invoice, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_one_attached :slip

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, :reference_number, :received_at, :payment_method, presence: true
  validates :payment_method, inclusion: { in: ArPayment::PAYMENT_METHODS }
  validates :slip, presence: true, on: :create
  validates :rejection_reason, presence: true, if: :rejected?
  # Agents settle a specific outstanding invoice via manual bank transfer, not a free-floating
  # claim to be allocated later — every new submission must target one. Only enforced on create
  # so submissions recorded before this requirement (nil ar_invoice) can still be approved/rejected.
  validates :ar_invoice, presence: true, on: :create
  validate :hotel_corporate_account_matches_hotel
  validate :ar_invoice_matches_hotel_corporate_account
  validate :amount_does_not_exceed_invoice_outstanding

  scope :pending, -> { where(status: "pending") }

  def approve!(ar_payment:, reviewed_by:)
    update!(status: "approved", ar_payment: ar_payment, reviewed_by: reviewed_by, reviewed_at: Time.current)
  end

  def reject!(reason:, reviewed_by:)
    update(status: "rejected", rejection_reason: reason, reviewed_by: reviewed_by, reviewed_at: Time.current)
  end

  private

  def hotel_corporate_account_matches_hotel
    return if hotel.blank? || hotel_corporate_account.blank?
    return if hotel_corporate_account.hotel_id == hotel_id

    errors.add(:hotel_corporate_account, "must belong to the submission hotel")
  end

  def ar_invoice_matches_hotel_corporate_account
    return if ar_invoice.blank? || hotel_corporate_account.blank?
    return if ar_invoice.hotel_corporate_account_id == hotel_corporate_account_id

    errors.add(:ar_invoice, "must belong to the same corporate account")
  end

  def amount_does_not_exceed_invoice_outstanding
    return if ar_invoice.blank? || amount.blank?
    return if amount.to_d <= ar_invoice.outstanding_amount.to_d

    errors.add(:amount, "cannot exceed the invoice's outstanding balance")
  end
end
