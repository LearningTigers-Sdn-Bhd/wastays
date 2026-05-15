# frozen_string_literal: true

class FolioTransaction < ApplicationRecord
  belongs_to :booking_folio
  belongs_to :user, optional: true

  enum :transaction_type, {
    charge: "charge",
    payment: "payment",
    adjustment: "adjustment"
  }

  validates :amount, presence: true, numericality: true
  validates :transaction_type, presence: true
  validates :category, presence: true
  validates :posting_date, presence: true

  scope :charges, -> { where(transaction_type: :charge) }
  scope :payments, -> { where(transaction_type: :payment) }
  scope :adjustments, -> { where(transaction_type: :adjustment) }

  def self.total_amount
    sum(:amount)
  end
end
