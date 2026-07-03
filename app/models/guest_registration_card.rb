# frozen_string_literal: true

class GuestRegistrationCard < ApplicationRecord
  STATUSES = %w[draft signed].freeze

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

  private

  def hotel_matches_booking
    return if hotel.blank? || booking.blank? || hotel_id == booking.hotel_id

    errors.add(:hotel, "must match booking hotel")
  end
end
