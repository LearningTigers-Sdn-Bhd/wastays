# frozen_string_literal: true

class GroupBillingChangeBatch < ApplicationRecord
  belongs_to :hotel
  belongs_to :group_booking
  belongs_to :actor, class_name: "User", optional: true

  validates :idempotency_key, :payload_digest, :status, presence: true
  validates :idempotency_key, uniqueness: { scope: :group_booking_id }
  validates :status, inclusion: { in: %w[pending completed] }
  validate :group_belongs_to_hotel

  private

  def group_belongs_to_hotel
    errors.add(:group_booking, "must belong to hotel") if group_booking && group_booking.hotel_id != hotel_id
  end
end
