# frozen_string_literal: true

class ArPaymentSubmission < ApplicationRecord
  STATUSES = %w[pending approved rejected].freeze

  belongs_to :hotel
  belongs_to :hotel_corporate_account
  belongs_to :submitted_by, class_name: "User"
  belongs_to :ar_payment, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_many :ar_payment_submission_allocations, dependent: :destroy, inverse_of: :ar_payment_submission
  has_many :ar_invoices, through: :ar_payment_submission_allocations

  accepts_nested_attributes_for :ar_payment_submission_allocations

  has_one_attached :slip

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, :reference_number, :received_at, :payment_method, presence: true
  validates :payment_method, inclusion: { in: ArPayment::PAYMENT_METHODS }
  validates :slip, presence: true, on: :create
  validates :rejection_reason, presence: true, if: :rejected?
  validate :hotel_corporate_account_matches_hotel
  # Agents settle specific outstanding invoice(s) via manual bank transfer — one remittance can
  # cover several invoices at once, but it must always target at least one. Only enforced on
  # create so submissions recorded before this requirement can still be approved/rejected.
  validate :has_at_least_one_allocation, on: :create
  validate :allocations_total_matches_amount

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

  def active_allocations
    ar_payment_submission_allocations.reject(&:marked_for_destruction?)
  end

  def has_at_least_one_allocation
    errors.add(:base, "must target at least one outstanding invoice") if active_allocations.empty?
  end

  def allocations_total_matches_amount
    return if amount.blank? || active_allocations.empty?

    total = active_allocations.sum { |allocation| allocation.amount.to_d }
    errors.add(:amount, "must equal the sum of the allocated invoice amounts") if total != amount.to_d
  end
end
