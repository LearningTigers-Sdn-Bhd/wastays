# frozen_string_literal: true

class FolioTransaction < ApplicationRecord
  CHARGE_CATEGORIES = %w[accommodation tax fb parking no_show_charge cancellation_charge late_checkout_charge early_departure_charge other].freeze
  PAYMENT_CATEGORIES = %w[gateway_payment cash refund booking_payment].freeze
  ADJUSTMENT_CATEGORIES = %w[adjustment correction discount write_off other].freeze
  CATEGORIES_BY_TYPE = {
    "charge" => CHARGE_CATEGORIES,
    "payment" => PAYMENT_CATEGORIES,
    "adjustment" => ADJUSTMENT_CATEGORIES
  }.freeze

  GL_MAPPABLE_CATEGORIES = (CATEGORIES_BY_TYPE.values.flatten + %w[security_deposits]).uniq.freeze

  PERMISSION_MAPPING = {
    "charge" => "post_folio_charges",
    "payment" => {
      "cash" => "post_folio_payments",
      "refund" => "execute_folio_refunds",
      "gateway_payment" => "post_folio_payments",
      "booking_payment" => "post_folio_payments"
    },
    "adjustment" => {
      "adjustment" => "post_folio_adjustments",
      "discount" => "post_folio_adjustments",
      "correction" => "post_folio_corrections",
      "write_off" => "post_folio_write_offs",
      "other" => "post_folio_adjustments"
    }
  }.freeze

  belongs_to :booking_folio
  belongs_to :transaction_code, optional: true
  belongs_to :night_audit, optional: true
  belongs_to :user, optional: true
  belongs_to :reversal_of_transaction, class_name: "FolioTransaction", optional: true
  belongs_to :voided_by_transaction, class_name: "FolioTransaction", optional: true
  belongs_to :parent_transaction, class_name: "FolioTransaction", optional: true
  belongs_to :split_from_transaction, class_name: "FolioTransaction", optional: true
  belongs_to :moved_from_transaction, class_name: "FolioTransaction", optional: true
  has_many :financial_audit_events, dependent: :restrict_with_error
  has_many :folio_operation_logs, foreign_key: :source_transaction_id, dependent: :restrict_with_error
  has_one :reversal_transaction,
    class_name: "FolioTransaction",
    foreign_key: :reversal_of_transaction_id,
    inverse_of: :reversal_of_transaction
  has_many :child_transactions,
    class_name: "FolioTransaction",
    foreign_key: :parent_transaction_id,
    inverse_of: :parent_transaction,
    dependent: :restrict_with_error
  has_one :group_deposit_allocation, dependent: :restrict_with_error

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
  validates :currency, presence: true
  validates :posting_date, presence: true
  validate :category_allowed_for_transaction_type
  validate :amount_sign_matches_transaction_type
  validate :reversal_reference_is_valid
  validate :lineage_references_are_valid
  validate :night_audit_matches_hotel
  validate :night_audit_matches_metadata, on: :create

  before_validation :assign_transaction_code, on: :create
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

  def self.permission_for(transaction_type, category)
    mapping = PERMISSION_MAPPING[transaction_type.to_s]
    return mapping if mapping.is_a?(String)

    mapping&.[](category.to_s)
  end

  def reversed?
    voided_by_transaction_id.present?
  end

  private

  def assign_gl_code
    return if gl_code.present? || hotel.blank?

    mapping = hotel.hotel_general_ledger_maps.find_by(transaction_category: category) if category.present?
    self.gl_code = mapping&.gl_code.presence || transaction_code&.gl_account_code
  end

  def assign_transaction_code
    return if transaction_code.present? || category.blank? || hotel.blank? || !hotel.persisted?

    Financials::EnsureDefaultTransactionCodes.call(hotel)
    self.transaction_code = tax_transaction_code || category_transaction_code
  end

  def tax_transaction_code
    return unless category == "tax"

    tax_line = metadata.to_h["tax_line"].presence || metadata.to_h[:tax_line].presence || {}
    tax_id = tax_line["tax_id"].presence || tax_line[:tax_id].presence
    if tax_id.present?
      tax = hotel.hotel_taxes.find_by(id: tax_id)
      return tax.ensure_transaction_code if tax.present?
    end

    tax_type = tax_line["type"].presence || tax_line[:type].presence
    system_key =
      case tax_type.to_s
      when "sst" then "sst_tax"
      when "tourism_tax" then "tourism_tax"
      end
    return if system_key.blank?

    hotel.transaction_codes.find_by(system_key: system_key)
  end

  def category_transaction_code
    system_key = Financials::EnsureDefaultTransactionCodes.system_key_for_category(category)
    return if system_key.blank?

    hotel.transaction_codes.find_by(system_key: system_key)
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

  def lineage_references_are_valid
    validate_lineage_reference(parent_transaction, :parent_transaction, same_folio: true)
    validate_lineage_reference(split_from_transaction, :split_from_transaction)
    validate_lineage_reference(moved_from_transaction, :moved_from_transaction)
  end

  def validate_lineage_reference(reference, attribute, same_folio: false)
    return if reference.blank?

    if reference == self
      errors.add(attribute, "can't reference itself")
    elsif same_folio && booking_folio_id.present? && reference.booking_folio_id != booking_folio_id
      errors.add(attribute, "must belong to the same folio")
    elsif !same_folio && booking_folio&.booking_id.present? && reference.booking_folio&.booking_id != booking_folio.booking_id
      errors.add(attribute, "must belong to the same booking")
    end
  end

  def night_audit_matches_hotel
    return if night_audit.blank? || booking_folio.blank? || night_audit.hotel_id == booking_folio.hotel_id

    errors.add(:night_audit, "must belong to the same hotel as the folio")
  end

  def night_audit_matches_metadata
    return if night_audit.blank?

    metadata_id = metadata.to_h["night_audit_id"] || metadata.to_h[:night_audit_id]
    return if metadata_id.present? && metadata_id.to_s == night_audit_id.to_s

    errors.add(:night_audit, "must match metadata night_audit_id")
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
