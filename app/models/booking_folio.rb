# frozen_string_literal: true

class BookingFolio < ApplicationRecord
  belongs_to :hotel
  belongs_to :booking
  has_many :folio_transactions, dependent: :restrict_with_error
  has_many :financial_audit_events, dependent: :restrict_with_error

  validates :folio_number, presence: true, uniqueness: { scope: :hotel_id }
  validates :status, presence: true
  validates :invoice_number, uniqueness: { scope: :hotel_id, allow_nil: true }
  validate :hotel_matches_booking

  def outstanding_balance
    total_charges - total_payments + total_adjustments
  end

  def total_charges
    folio_transactions.charge.sum(:amount)
  end

  def total_payments
    folio_transactions.payment.sum(:amount)
  end

  def total_adjustments
    folio_transactions.adjustment.sum(:amount)
  end

  private

  def hotel_matches_booking
    return if hotel_id.blank? || booking.blank? || hotel_id == booking.hotel_id

    errors.add(:hotel, "must match booking hotel")
  end
end
