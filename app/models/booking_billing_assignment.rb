# frozen_string_literal: true

class BookingBillingAssignment < ApplicationRecord
  belongs_to :booking
  belongs_to :group_billing_arrangement
  has_many :folio_routing_rules, dependent: :restrict_with_error

  validates :charge_category, presence: true, uniqueness: { scope: :booking_id }
  validate :booking_belongs_to_arrangement_group
  validate :effective_dates_are_ordered

  private

  def booking_belongs_to_arrangement_group
    return if booking.blank? || group_billing_arrangement.blank?
    return if booking.group_booking_id == group_billing_arrangement.group_booking_id

    errors.add(:booking, "must belong to the arrangement's group")
  end

  def effective_dates_are_ordered
    return if effective_from.blank? || effective_until.blank? || effective_until >= effective_from

    errors.add(:effective_until, "must be on or after effective from")
  end
end
