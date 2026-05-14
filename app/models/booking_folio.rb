# frozen_string_literal: true

class BookingFolio < ApplicationRecord
  belongs_to :booking

  validates :folio_number, presence: true, uniqueness: true
  validates :status, presence: true

  def outstanding_balance
    # Placeholder for future itemized charges
    0.0
  end
end
