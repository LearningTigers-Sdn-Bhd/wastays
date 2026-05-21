# frozen_string_literal: true

class Deposit < ApplicationRecord
  HOLD_TYPES = %w[security].freeze
  STATUSES = %w[pending authorized collected released forfeited failed].freeze

  belongs_to :hotel
  belongs_to :booking
  belongs_to :booking_folio, optional: true
  belongs_to :user, optional: true

  validates :hold_type, presence: true, inclusion: { in: HOLD_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, presence: true
  validate :hotel_matches_booking
  validate :folio_matches_booking

  before_validation :set_defaults, on: :create
  before_validation :assign_gl_code, on: :create

  private

  def set_defaults
    self.hold_type ||= "security"
    self.status ||= "collected"
    self.currency ||= booking&.currency || hotel&.default_currency || "MYR"
    self.collected_at ||= Time.current if status == "collected"
  end

  def assign_gl_code
    return if gl_code.present? || hotel.blank?

    self.gl_code = hotel.hotel_general_ledger_maps.find_by(transaction_category: "security_deposits")&.gl_code
  end

  def hotel_matches_booking
    return if hotel_id.blank? || booking.blank? || hotel_id == booking.hotel_id

    errors.add(:hotel, "must match booking hotel")
  end

  def folio_matches_booking
    return if booking_folio.blank? || booking_folio.booking_id == booking_id

    errors.add(:booking_folio, "must belong to the same booking")
  end
end
