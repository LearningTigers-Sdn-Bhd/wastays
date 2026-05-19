# frozen_string_literal: true

class BookingFolio < ApplicationRecord
  belongs_to :hotel
  belongs_to :booking
  has_many :folio_transactions, dependent: :restrict_with_error

  validates :folio_number, presence: true, uniqueness: { scope: :hotel_id }
  validates :status, presence: true
  validate :hotel_matches_booking

  def outstanding_balance
    folio_transactions.charge.sum(:amount) -
      folio_transactions.payment.sum(:amount) +
      folio_transactions.adjustment.sum(:amount)
  end

  private

  def hotel_matches_booking
    return if hotel_id.blank? || booking.blank? || hotel_id == booking.hotel_id

    errors.add(:hotel, "must match booking hotel")
  end
end
