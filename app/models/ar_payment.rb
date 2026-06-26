# frozen_string_literal: true

class ArPayment < ApplicationRecord
  PAYMENT_METHODS = %w[bank_transfer cheque cash card other].freeze

  belongs_to :hotel
  belongs_to :hotel_corporate_account
  has_many :ar_payment_allocations, dependent: :restrict_with_error
  has_many :ar_invoices, through: :ar_payment_allocations

  delegate :corporate_account, to: :hotel_corporate_account

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, :reference_number, :received_at, :payment_method, presence: true
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }
  validates :metadata, exclusion: { in: [ nil ] }
  validate :hotel_corporate_account_matches_hotel

  def allocated_amount
    if ar_payment_allocations.loaded?
      ar_payment_allocations.reject(&:reversed?).sum { |allocation| allocation.amount.to_d }
    else
      ar_payment_allocations.active.sum(:amount)
    end
  end

  def unallocated_amount
    amount.to_d - allocated_amount.to_d
  end

  def allocation_status
    return "unapplied" if allocated_amount.zero?
    return "fully_allocated" if unallocated_amount.zero?

    "partially_allocated"
  end

  before_update :prevent_update
  before_destroy :prevent_destroy

  private

  def prevent_update
    errors.add(:base, "AR payments are immutable.")
    throw :abort
  end

  def prevent_destroy
    errors.add(:base, "AR payments are immutable and cannot be deleted.")
    throw :abort
  end

  def hotel_corporate_account_matches_hotel
    return if hotel.blank? || hotel_corporate_account.blank?
    return if hotel_corporate_account.hotel_id == hotel_id

    errors.add(:hotel_corporate_account, "must belong to the payment hotel")
  end
end
