# frozen_string_literal: true

class GroupBooking < ApplicationRecord
  STATUSES = %w[draft active completed cancelled].freeze

  belongs_to :hotel
  belongs_to :organizer_guest, class_name: "Guest", optional: true
  has_many :bookings, -> { order(:group_position, :id) }, dependent: :restrict_with_error
  has_many :deposits, dependent: :restrict_with_error
  has_many :group_billing_change_batches, dependent: :restrict_with_error
  has_one :booking_confirmation_token, dependent: :destroy

  validates :confirmation_token, :name, :status, presence: true
  validates :confirmation_token, uniqueness: true
  validates :reservation_number, uniqueness: { scope: [ :hotel_id, :reservation_year ], allow_nil: true }
  validates :receipt_number, uniqueness: { scope: :hotel_id, allow_nil: true }
  validates :channel_manager_reference, uniqueness: { scope: :hotel_id, allow_blank: true }
  validates :external_reference, uniqueness: { scope: :hotel_id, allow_blank: true }
  validates :status, inclusion: { in: STATUSES }
  validate :organizer_guest_belongs_to_hotel
  validate :default_dates_are_ordered

  before_validation :assign_confirmation_token, on: :create
  before_validation :assign_existing_document_reference
  before_create :assign_document_counters
  after_create :register_confirmation_token
  after_update :sync_confirmation_token, if: :saved_change_to_confirmation_token?

  scope :with_confirmation_token, ->(token) {
    joins(:booking_confirmation_token).where(booking_confirmation_tokens: { token: token.to_s.strip.upcase })
  }

  def formatted_reservation_number
    reservation_reference.presence || DocumentIdentifiers::Issuer.format(hotel:, type: :reservation, year: reservation_year, number: reservation_number)
  end

  def formatted_receipt_number
    DocumentIdentifiers::Issuer.format(hotel:, type: :receipt, year: created_at&.year, number: receipt_number)
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

  def register_confirmation_token
    DocumentIdentifiers::RegisterConfirmationToken.call!(record: self)
  end

  def sync_confirmation_token
    DocumentIdentifiers::SyncConfirmationToken.call!(record: self)
  end

  def assign_document_counters
    return if reservation_number.present? && reservation_year.present? && reservation_reference.present?

    allocation = DocumentIdentifiers::Issuer.issue!(hotel:, type: :reservation)
    self.reservation_number = allocation.number
    self.reservation_year = allocation.year
    self.reservation_reference = allocation.reference
  end

  def assign_existing_document_reference
    self.reservation_year ||= DocumentIdentifiers::Issuer.sequence_year(hotel:) if hotel && reservation_number.present?
    self.reservation_reference ||= DocumentIdentifiers::Issuer.format(hotel:, type: :reservation, year: reservation_year, number: reservation_number)
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
