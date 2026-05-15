# frozen_string_literal: true

class BookingFolio < ApplicationRecord
  belongs_to :booking
  has_many :folio_transactions, dependent: :destroy

  validates :folio_number, presence: true, uniqueness: true
  validates :status, presence: true

  def outstanding_balance
    folio_transactions.charge.sum(:amount) -
      folio_transactions.payment.sum(:amount) +
      folio_transactions.adjustment.sum(:amount)
  end
end
