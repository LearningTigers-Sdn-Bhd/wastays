# frozen_string_literal: true

# Expand-contract adapter: receivables retain the ar_invoices table and primary
# keys until the final contract release renames the table and foreign keys.
class Receivable < ApplicationRecord
  self.table_name = "ar_invoices"

  STATUSES = %w[open partially_paid paid overdue void].freeze
  MUTABLE_FIELDS = %w[paid_amount outstanding_amount status metadata updated_at].freeze

  belongs_to :invoice, inverse_of: :receivable, optional: true
  belongs_to :hotel
  belongs_to :booking_folio
  belongs_to :hotel_corporate_account
  has_many :ar_payment_allocations, foreign_key: :ar_invoice_id, dependent: :restrict_with_error
  has_many :ar_payments, through: :ar_payment_allocations

  delegate :booking, to: :booking_folio
  delegate :corporate_account, to: :hotel_corporate_account

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :invoice_id, uniqueness: true, allow_nil: true
  validates :invoice_number, presence: true, uniqueness: { scope: [ :hotel_id, :invoice_year ] }
  validates :booking_folio_id, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :paid_amount, :outstanding_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, :issued_on, :due_on, presence: true
  validates :metadata, exclusion: { in: [ nil ] }
  validate :references_match_hotel
  validate :hotel_corporate_account_matches_folio
  validate :invoice_matches_receivable

  before_update :prevent_immutable_changes
  before_validation :assign_invoice_reference

  scope :with_open_balance, -> { where.not(status: %w[paid void]).where(arel_table[:outstanding_amount].gt(0)) }
  scope :due_before, ->(date) { where(arel_table[:due_on].lt(date)) }

  def overdue_as_of?(date = Date.current)
    outstanding_amount.to_d.positive? && due_on.present? && due_on < date.to_date && !paid? && !void?
  end

  def formatted_invoice_number
    invoice&.invoice_reference.presence || invoice_reference.presence ||
      DocumentIdentifiers::Issuer.format(hotel:, type: :ar_invoice, year: invoice_year, number: invoice_number)
  end

  private

  def assign_invoice_reference
    self.invoice_year ||= DocumentIdentifiers::Issuer.sequence_year(hotel:) if hotel && invoice_number.present?
    self.invoice_reference ||= DocumentIdentifiers::Issuer.format(hotel:, type: :ar_invoice, year: invoice_year, number: invoice_number)
  end

  def references_match_hotel
    return if hotel.blank?

    errors.add(:booking_folio, "must belong to the invoice hotel") if booking_folio.present? && booking_folio.hotel_id != hotel_id
    if hotel_corporate_account.present? && hotel_corporate_account.hotel_id != hotel_id
      errors.add(:hotel_corporate_account, "must belong to the invoice hotel")
    end
  end

  def hotel_corporate_account_matches_folio
    return if booking_folio.blank? || hotel_corporate_account.blank?
    return if booking_folio.hotel_corporate_account_id == hotel_corporate_account_id

    errors.add(:hotel_corporate_account, "must match the folio company account")
  end

  def invoice_matches_receivable
    return if invoice.blank?

    errors.add(:invoice, "must be a direct-bill document") unless invoice.kind_direct_bill?
    errors.add(:invoice, "must belong to the same folio") unless invoice.booking_folio_id == booking_folio_id
    errors.add(:invoice, "must belong to the same hotel") unless invoice.hotel_id == hotel_id
  end

  def prevent_immutable_changes
    immutable_changes = changes.keys - MUTABLE_FIELDS
    return if immutable_changes.empty?

    message = is_a?(ArInvoice) ?
      "AR invoices are immutable after creation except payment and status fields." :
      "Receivables are immutable after creation except payment and status fields."
    errors.add(:base, message)
    throw :abort
  end
end
