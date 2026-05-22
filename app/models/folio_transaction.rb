# frozen_string_literal: true

class FolioTransaction < ApplicationRecord
  CHARGE_CATEGORIES = %w[accommodation tax fb no_show_charge late_checkout_charge early_departure_charge other].freeze
  PAYMENT_CATEGORIES = %w[gateway_payment cash refund booking_payment].freeze
  ADJUSTMENT_CATEGORIES = %w[adjustment correction discount write_off other].freeze
  CATEGORIES_BY_TYPE = {
    "charge" => CHARGE_CATEGORIES,
    "payment" => PAYMENT_CATEGORIES,
    "adjustment" => ADJUSTMENT_CATEGORIES
  }.freeze

  GL_MAPPABLE_CATEGORIES = (CATEGORIES_BY_TYPE.values.flatten + %w[security_deposits]).uniq.freeze

  belongs_to :booking_folio
  belongs_to :user, optional: true
  belongs_to :reversal_of_transaction, class_name: "FolioTransaction", optional: true
  belongs_to :voided_by_transaction, class_name: "FolioTransaction", optional: true
  has_many :financial_audit_events, dependent: :restrict_with_error
  has_one :reversal_transaction,
    class_name: "FolioTransaction",
    foreign_key: :reversal_of_transaction_id,
    inverse_of: :reversal_of_transaction

  delegate :hotel, to: :booking_folio, allow_nil: true

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
  validate :reversal_reference_is_valid

  before_validation :assign_gl_code, on: :create
  before_update :prevent_immutable_changes
  before_destroy :prevent_destroy

  scope :charges, -> { where(transaction_type: :charge) }
  scope :payments, -> { where(transaction_type: :payment) }
  scope :adjustments, -> { where(transaction_type: :adjustment) }

  def self.total_amount
    sum(:amount)
  end

  def self.gl_mappable_categories
    GL_MAPPABLE_CATEGORIES
  end

  def reversed?
    voided_by_transaction_id.present?
  end

  private

  def assign_gl_code
    return if gl_code.present? || category.blank? || hotel.blank?

    mapping = hotel.hotel_general_ledger_maps.find_by(transaction_category: category)
    self.gl_code = mapping&.gl_code
  end

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

  def reversal_reference_is_valid
    return if reversal_of_transaction.blank?

    if reversal_of_transaction == self
      errors.add(:reversal_of_transaction, "can't reference itself")
    elsif booking_folio_id.present? && reversal_of_transaction.booking_folio_id != booking_folio_id
      errors.add(:reversal_of_transaction, "must belong to the same folio")
    end
  end

  def prevent_immutable_changes
    immutable_changes = changes.keys - %w[voided_by_transaction_id updated_at]
    return if immutable_changes.empty?

    errors.add(:base, "Folio transactions are immutable. Post a reversing transaction instead.")
    throw :abort
  end

  def prevent_destroy
    errors.add(:base, "Folio transactions are immutable and cannot be deleted.")
    throw :abort
  end
end
