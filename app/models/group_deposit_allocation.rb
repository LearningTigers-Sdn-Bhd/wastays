# frozen_string_literal: true

class GroupDepositAllocation < ApplicationRecord
  belongs_to :group_deposit
  belongs_to :booking
  belongs_to :booking_folio
  belongs_to :folio_transaction, optional: true
  belongs_to :allocated_by, class_name: "User", optional: true
  belongs_to :reversal_of, class_name: "GroupDepositAllocation", optional: true
  has_one :reversal, class_name: "GroupDepositAllocation", foreign_key: :reversal_of_id, dependent: :restrict_with_error

  scope :active, -> { where(status: "active") }

  validates :amount, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[active reversed] }
  validates :allocated_at, presence: true
  validate :targets_group_child
  validate :folio_belongs_to_booking

  private

  def targets_group_child
    return if booking.blank? || group_deposit.blank?
    return if booking.group_booking_id == group_deposit.group_booking_id

    errors.add(:booking, "must belong to the deposit's group")
  end

  def folio_belongs_to_booking
    return if booking_folio.blank? || booking.blank? || booking_folio.booking_id == booking.id

    errors.add(:booking_folio, "must belong to the selected booking")
  end
end
