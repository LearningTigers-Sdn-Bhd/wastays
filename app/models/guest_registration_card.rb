# frozen_string_literal: true

class GuestRegistrationCard < ApplicationRecord
  STATUSES = %w[draft signed].freeze
  DISPLAY_FIELDS = {
    "phone" => "Phone",
    "email" => "Email",
    "guest_count" => "Guest count",
    "room_type" => "Room type",
    "room_number" => "Room number",
    "booking_number" => "Booking number",
    "check_in" => "Check-in",
    "check_out" => "Check-out"
  }.freeze

  belongs_to :hotel
  belongs_to :booking

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :booking_id, uniqueness: true
  validates :signer_name, presence: true, if: :signed?
  validates :signature_data_url, presence: true, if: :signed?
  validate :hotel_matches_booking

  def capture_terms_snapshot_preview
    policy = hotel.property_policy

    {
      "check_in_time" => policy&.check_in_time,
      "check_out_time" => policy&.check_out_time,
      "cancellation_policy" => policy&.cancellation_policy
    }.compact
  end

  def capture_terms_snapshot!
    update!(terms_snapshot: capture_terms_snapshot_preview)
    terms_snapshot
  end

  def capture_display_fields_snapshot
    sanitize_display_fields(hotel.guest_registration_card_fields)
  end

  def visible_fields
    fields = signed? ? display_fields_snapshot : hotel.guest_registration_card_fields
    sanitize_display_fields(fields)
  end

  def field_visible?(key)
    key.to_s.in?(visible_fields)
  end

  private

  def sanitize_display_fields(fields)
    return DISPLAY_FIELDS.keys if fields.nil?

    Array(fields).map(&:to_s) & DISPLAY_FIELDS.keys
  end

  def hotel_matches_booking
    return if hotel.blank? || booking.blank? || hotel_id == booking.hotel_id

    errors.add(:hotel, "must match booking hotel")
  end
end
