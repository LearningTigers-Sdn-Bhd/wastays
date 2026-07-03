# frozen_string_literal: true

class GroupBooking < ApplicationRecord
  STATUSES = %w[draft active completed cancelled].freeze

  belongs_to :hotel
  belongs_to :organizer_guest, class_name: "Guest", optional: true
  has_many :bookings, -> { order(:group_position, :id) }, dependent: :restrict_with_error
  has_many :group_billing_arrangements, dependent: :restrict_with_error
  has_many :group_deposits, dependent: :restrict_with_error

  validates :reference, :name, :status, presence: true
  validates :reference, uniqueness: { scope: :hotel_id }
  validates :status, inclusion: { in: STATUSES }
  validate :organizer_guest_belongs_to_hotel
  validate :default_dates_are_ordered

  def projected_status
    child_statuses = bookings.reorder(nil).pluck(:status)
    return "draft" if child_statuses.empty?
    return "cancelled" if child_statuses.all? { |status| status == "cancelled" }
    return "completed" if child_statuses.all? { |status| status.in?(%w[completed cancelled]) }

    "active"
  end

  private

  def organizer_guest_belongs_to_hotel
    return if organizer_guest.blank? || organizer_guest.created_by_hotel_id.blank?
    return if organizer_guest.created_by_hotel_id == hotel_id

    errors.add(:organizer_guest, "must belong to the same hotel")
  end

  def default_dates_are_ordered
    return if default_check_in.blank? || default_check_out.blank? || default_check_out > default_check_in

    errors.add(:default_check_out, "must be after default check-in")
  end
end
