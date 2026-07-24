# frozen_string_literal: true

class Deposit < ApplicationRecord
  HOLD_TYPES = %w[security].freeze
  STATUSES = %w[pending authorized held collected released forfeited failed].freeze

  belongs_to :hotel
  belongs_to :booking
  belongs_to :booking_folio, optional: true
  belongs_to :transaction_code, optional: true
  belongs_to :user, optional: true

  validates :hold_type, presence: true, inclusion: { in: HOLD_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validates :transaction_code, presence: true
  validate :hotel_matches_booking
  validate :folio_matches_booking
  validate :transaction_code_matches_hotel
  validate :transaction_code_is_security_deposit

  before_validation :set_defaults, on: :create
  before_validation :assign_transaction_code, on: :create

  private

  def set_defaults
    self.hold_type ||= "security"
    self.status ||= "held"
    self.currency ||= booking&.currency || hotel&.default_currency || "MYR"
    self.collected_at ||= Time.current if status.in?(%w[held collected])
  end

  def assign_transaction_code
    return if transaction_code.present? || hotel.blank?

    Financials::EnsureDefaultTransactionCodes.call(hotel)
    self.transaction_code = TransactionCodes::Resolver.for(hotel).for_key("security_deposit")
  end

  def hotel_matches_booking
    return if hotel_id.blank? || booking.blank? || hotel_id == booking.hotel_id

    errors.add(:hotel, "must match booking hotel")
  end

  def folio_matches_booking
    return if booking_folio.blank? || booking_folio.booking_id == booking_id

    errors.add(:booking_folio, "must belong to the same booking")
  end

  def transaction_code_matches_hotel
    return if transaction_code.blank? || hotel_id.blank? || transaction_code.hotel_id == hotel_id

    errors.add(:transaction_code, "must belong to the same hotel")
  end

  def transaction_code_is_security_deposit
    return if transaction_code.blank?
    return if transaction_code.system_key == "security_deposit" && transaction_code.category == "security_deposit"

    errors.add(:transaction_code, "must be a security deposit code")
  end
end
