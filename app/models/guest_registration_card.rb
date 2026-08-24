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
  belongs_to :booking_guest, optional: true

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :booking_guest_id, uniqueness: true, allow_nil: true
  validates :signer_name, presence: true, if: :signed?
  validates :signature_data_url, presence: true, if: :signed?
  validates :public_token, presence: true, uniqueness: true
  validate :hotel_matches_booking

  before_validation :generate_public_token, on: :create

  # The terms as they stand when the guest signs. `cancellation_policy_data` carries
  # the tier table; `cancellation_policy` keeps the flat text for readers that have
  # not moved over yet, and for cards signed before policies became structured.
  def capture_terms_snapshot_preview
    policy = hotel.property_policy
    cancellation = Cancellations::PolicySummary.for_hotel(hotel)

    {
      "check_in_time" => policy&.check_in_time,
      "check_out_time" => policy&.check_out_time,
      "cancellation_policy_data" => Cancellations::PolicySummary.snapshot_for(hotel).presence,
      "cancellation_policy" => cancellation.to_text.presence || policy&.cancellation_policy,
      "terms_and_conditions" => hotel.guest_registration_card_terms.presence
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

  # Signing, printing, and sending all need a hotel policy to show the guest.
  # A card that has already been signed carries its own snapshot regardless of
  # what the hotel's live setting says now, so it never gets retroactively
  # blocked by an edit made after the guest agreed to it.
  def ready_for_guest?
    signed? || hotel.guest_registration_card_terms.present?
  end

  def signed_for_guest?
    signed? && signature_data_url.present?
  end

  def save_signature_for_guest!(signer_name:, signature_data_url:, signed_at: Time.current)
    assign_attributes(
      signer_name: signer_name,
      signature_data_url: signature_data_url,
      status: "signed",
      signed_at: signed_at,
      terms_snapshot: capture_terms_snapshot_preview,
      display_fields_snapshot: capture_display_fields_snapshot
    )
    save!
  end

  def remove_signature_for_guest!
    update!(
      status: "draft",
      signer_name: nil,
      signature_data_url: nil,
      signed_at: nil,
      display_fields_snapshot: nil
    )
  end

  private

  def generate_public_token
    self.public_token ||= SecureRandom.hex(20)
  end

  def sanitize_display_fields(fields)
    return DISPLAY_FIELDS.keys if fields.nil?

    Array(fields).map(&:to_s) & DISPLAY_FIELDS.keys
  end

  def hotel_matches_booking
    return if hotel.blank? || booking.blank? || hotel_id == booking.hotel_id

    errors.add(:hotel, "must match booking hotel")
  end
end
