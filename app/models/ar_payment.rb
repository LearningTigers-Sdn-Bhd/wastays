# frozen_string_literal: true

class ArPayment < ApplicationRecord
  PAYMENT_METHODS = %w[bank_transfer cheque cash card other].freeze

  belongs_to :hotel
  belongs_to :hotel_corporate_account
  has_many :ar_payment_allocations, dependent: :restrict_with_error
  has_many :ar_invoices, through: :ar_payment_allocations
  has_one :receipt, dependent: :restrict_with_error
  has_one :void, class_name: "ArPaymentVoid", dependent: :restrict_with_error, inverse_of: :ar_payment
  # The agent's remittance proof, when the payment was approved from one. The
  # slip has to stay reachable from the payment after approval — it is the
  # evidence behind the money.
  has_one :ar_payment_submission, dependent: :nullify, inverse_of: :ar_payment

  scope :not_voided, -> { where.missing(:void) }

  after_create :issue_payment_receipt

  delegate :corporate_account, to: :hotel_corporate_account

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, :reference_number, :received_at, :payment_method, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :metadata, exclusion: { in: [ nil ] }
  validate :hotel_corporate_account_matches_hotel

  def allocated_amount
    if ar_payment_allocations.loaded?
      ar_payment_allocations.reject(&:reversed?).sum { |allocation| allocation.amount.to_d }
    else
      ar_payment_allocations.active.sum(:amount)
    end
  end

  # A voided payment holds no funds, so it never counts as unapplied credit.
  def unallocated_amount
    return 0.to_d if voided?

    amount.to_d - allocated_amount.to_d
  end

  def voided?
    void.present?
  end

  # Gateway money has to go back through the gateway as a refund.
  def gateway_payment?
    metadata.to_h["source"] == "corporate_portal_gateway" ||
      CorporateArPaymentIntent.exists?(ar_payment_id: id) ||
      PaymentTransaction.exists?(ar_payment_id: id)
  end

  def allocation_status
    return "voided" if voided?
    return "unapplied" if allocated_amount.zero?
    return "fully_allocated" if unallocated_amount.zero?

    "partially_allocated"
  end

  before_update :prevent_update
  before_destroy :prevent_destroy

  private

  def issue_payment_receipt
    Receipts::Issue.call!(source: self)
  end

  def prevent_update
    errors.add(:base, "AR payments are immutable.")
    throw :abort
  end

  def prevent_destroy
    errors.add(:base, "AR payments are immutable and cannot be deleted.")
    throw :abort
  end

  def hotel_corporate_account_matches_hotel
    return if hotel.blank? || hotel_corporate_account.blank?
    return if hotel_corporate_account.hotel_id == hotel_id

    errors.add(:hotel_corporate_account, "must belong to the payment hotel")
  end
end
