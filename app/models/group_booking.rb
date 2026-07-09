# frozen_string_literal: true

class GroupBooking < ApplicationRecord
  STATUSES = %w[draft active completed cancelled].freeze

  belongs_to :hotel
  belongs_to :organizer_guest, class_name: "Guest", optional: true
  has_many :bookings, -> { order(:group_position, :id) }, dependent: :restrict_with_error
  has_many :group_deposits, dependent: :restrict_with_error
  has_many :group_billing_change_batches, dependent: :restrict_with_error

  validates :confirmation_token, :name, :status, presence: true
  validates :confirmation_token, uniqueness: true
  validates :reservation_number, uniqueness: { scope: :hotel_id, allow_nil: true }
  validates :receipt_number, uniqueness: { scope: :hotel_id, allow_nil: true }
  validates :status, inclusion: { in: STATUSES }
  validate :organizer_guest_belongs_to_hotel
  validate :default_dates_are_ordered

  before_validation :assign_confirmation_token, on: :create
  before_create :assign_document_counters

  def formatted_reservation_number
    format_number(reservation_number, type_code: 1)
  end

  def formatted_receipt_number
    format_number(receipt_number, type_code: 5)
  end

  def projected_status
    child_statuses = bookings.reorder(nil).pluck(:status)
    return "draft" if child_statuses.empty?
    return "cancelled" if child_statuses.all? { |status| status == "cancelled" }
    return "completed" if child_statuses.all? { |status| status.in?(%w[completed cancelled]) }

    "active"
  end

  private

  def assign_confirmation_token
    DocumentIdentifiers::HotelReferences.assign_confirmation_token(self, unique_against: [ Booking, GroupBooking ])
  end

  def assign_document_counters
    DocumentIdentifiers::HotelReferences.assign_counter(self, attribute: :reservation_number, counter_type: "reservation")
    DocumentIdentifiers::HotelReferences.assign_counter(self, attribute: :receipt_number, counter_type: "receipt")
  end

  def format_number(number, type_code:)
    DocumentIdentifiers::HotelReferences.format(hotel: hotel, number: number, type_code: type_code)
  end

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
