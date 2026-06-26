# frozen_string_literal: true

class ArInvoice < ApplicationRecord
  STATUSES = %w[open partially_paid paid overdue void].freeze
  MUTABLE_FIELDS = %w[paid_amount outstanding_amount status metadata updated_at].freeze
  DOCUMENT_NUMBER_PAD_LENGTH = 7
  DOCUMENT_TYPE_CODE = 4

  belongs_to :hotel
  belongs_to :booking_folio
  belongs_to :hotel_corporate_account
  has_many :ar_payment_allocations, dependent: :restrict_with_error
  has_many :ar_payments, through: :ar_payment_allocations

  delegate :booking, to: :booking_folio
  delegate :corporate_account, to: :hotel_corporate_account

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :invoice_number, presence: true, uniqueness: { scope: :hotel_id }
  validates :booking_folio_id, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :paid_amount, :outstanding_amount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, :issued_on, :due_on, presence: true
  validates :metadata, exclusion: { in: [ nil ] }
  validate :references_match_hotel
  validate :hotel_corporate_account_matches_folio

  before_update :prevent_immutable_changes

  scope :with_open_balance, -> { where.not(status: %w[paid void]).where(arel_table[:outstanding_amount].gt(0)) }
  scope :due_before, ->(date) { where(arel_table[:due_on].lt(date)) }

  def overdue_as_of?(date = Date.current)
    outstanding_amount.to_d.positive? && due_on.present? && due_on < date.to_date && !paid? && !void?
  end

  def formatted_invoice_number
    return nil unless invoice_number

    prefix = hotel&.hotel_prefix.presence || "WS"
    padded = invoice_number.to_s.rjust(DOCUMENT_NUMBER_PAD_LENGTH, "0")
    "#{prefix}-#{DOCUMENT_TYPE_CODE}#{padded}"
  end

  private

  def references_match_hotel
    return if hotel.blank?

    if booking_folio.present? && booking_folio.hotel_id != hotel_id
      errors.add(:booking_folio, "must belong to the invoice hotel")
    end

    if hotel_corporate_account.present? && hotel_corporate_account.hotel_id != hotel_id
      errors.add(:hotel_corporate_account, "must belong to the invoice hotel")
    end
  end

  def hotel_corporate_account_matches_folio
    return if booking_folio.blank? || hotel_corporate_account.blank?
    return if booking_folio.hotel_corporate_account_id == hotel_corporate_account_id

    errors.add(:hotel_corporate_account, "must match the folio company account")
  end

  def prevent_immutable_changes
    immutable_changes = changes.keys - MUTABLE_FIELDS
    return if immutable_changes.empty?

    errors.add(:base, "AR invoices are immutable after creation except payment and status fields.")
    throw :abort
  end
end
