# frozen_string_literal: true

class BookingConfirmationToken < ApplicationRecord
  belongs_to :booking, optional: true
  belongs_to :group_booking, optional: true

  validates :token, presence: true, uniqueness: true
  validate :exactly_one_owner

  def owner
    booking || group_booking
  end

  private

  def exactly_one_owner
    return if booking.present? ^ group_booking.present?

    errors.add(:base, "Confirmation token must belong to exactly one booking or group booking")
  end
end
