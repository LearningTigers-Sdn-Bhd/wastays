# frozen_string_literal: true

class FolioTransaction < ApplicationRecord
  CHARGE_CATEGORIES = %w[accommodation tax fb other].freeze
  PAYMENT_CATEGORIES = %w[gateway_payment cash refund advance_deposit].freeze
  ADJUSTMENT_CATEGORIES = %w[adjustment correction discount write_off other].freeze
  CATEGORIES_BY_TYPE = {
    "charge" => CHARGE_CATEGORIES,
    "payment" => PAYMENT_CATEGORIES,
    "adjustment" => ADJUSTMENT_CATEGORIES
  }.freeze

  belongs_to :booking_folio
  belongs_to :user, optional: true

  enum :transaction_type, {
    charge: "charge",
    payment: "payment",
    adjustment: "adjustment"
  }

  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :transaction_type, presence: true
  validates :category, presence: true
  validates :description, presence: true
  validates :posting_date, presence: true
  validate :category_allowed_for_transaction_type
  validate :amount_sign_matches_transaction_type

  scope :charges, -> { where(transaction_type: :charge) }
  scope :payments, -> { where(transaction_type: :payment) }
  scope :adjustments, -> { where(transaction_type: :adjustment) }

  def self.total_amount
    sum(:amount)
  end

  private

  def category_allowed_for_transaction_type
    return if transaction_type.blank? || category.blank?

    allowed_categories = CATEGORIES_BY_TYPE.fetch(transaction_type, [])
    return if category.in?(allowed_categories)

    errors.add(:category, "is not allowed for #{transaction_type} transactions")
  end

  def amount_sign_matches_transaction_type
    return if amount.blank? || transaction_type.blank? || category.blank?

    if charge? && amount.negative?
      errors.add(:amount, "must be positive for charge transactions")
    elsif payment? && category == "refund" && amount.positive?
      errors.add(:amount, "must be negative for refund transactions")
    elsif payment? && category != "refund" && amount.negative?
      errors.add(:amount, "must be positive for payment transactions")
    end
  end
end
