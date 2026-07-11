# frozen_string_literal: true

class GroupDeposit < ApplicationRecord
  STATUSES = %w[received partially_allocated allocated partially_refunded refunded cancelled].freeze

  belongs_to :group_booking
  belongs_to :hotel
  belongs_to :hotel_corporate_account, optional: true
  belongs_to :received_by, class_name: "User", optional: true
  has_many :group_deposit_allocations, dependent: :restrict_with_error

  validates :amount, numericality: { greater_than: 0 }
  validates :refunded_amount, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: :amount }
  validates :currency, :payment_method, :received_at, :status, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :external_reference, uniqueness: { scope: :hotel_id, allow_blank: true }
  validate :relationships_belong_to_hotel

  def allocated_amount
    group_deposit_allocations.active.sum(:amount)
  end

  def available_amount
    amount - allocated_amount - refunded_amount
  end

  private

  def relationships_belong_to_hotel
    errors.add(:group_booking, "must belong to the same hotel") if group_booking.present? && group_booking.hotel_id != hotel_id
    if hotel_corporate_account.present? && hotel_corporate_account.hotel_id != hotel_id
      errors.add(:hotel_corporate_account, "must belong to the same hotel")
    end
  end
end
