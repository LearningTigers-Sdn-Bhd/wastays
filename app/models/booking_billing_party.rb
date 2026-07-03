# frozen_string_literal: true

class BookingBillingParty < ApplicationRecord
  PARTY_KINDS = %w[guest company].freeze

  belongs_to :hotel
  belongs_to :booking
  belongs_to :booking_guest, optional: true
  belongs_to :hotel_corporate_account, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :booking_folios, dependent: :restrict_with_error
  has_one :billing_terms, class_name: "BookingBillingTerms", dependent: :destroy

  enum :party_kind, PARTY_KINDS.index_by(&:itself), validate: true

  validates :party_kind, presence: true
  validate :booking_belongs_to_hotel
  validate :exactly_one_identity
  validate :identity_matches_party_kind
  validate :booking_guest_belongs_to_booking
  validate :hotel_corporate_account_belongs_to_hotel

  scope :active, -> { where(archived_at: nil) }
  scope :guests, -> { where(party_kind: "guest") }
  scope :companies, -> { where(party_kind: "company") }

  def display_name
    case party_kind
    when "guest"
      booking_guest&.name_snapshot.presence || booking_guest&.guest&.name.presence || booking&.guest_name
    when "company"
      hotel_corporate_account&.corporate_account&.name
    end.presence || party_kind.to_s.humanize
  end

  def archiveable?
    company? && booking_folios.none?
  end

  private

  def booking_belongs_to_hotel
    return if booking.blank? || hotel_id.blank? || booking.hotel_id == hotel_id

    errors.add(:booking, "must belong to the same hotel")
  end

  def exactly_one_identity
    identities = [ booking_guest_id, hotel_corporate_account_id ].count(&:present?)
    return if identities == 1

    errors.add(:base, "must reference exactly one billing identity")
  end

  def identity_matches_party_kind
    case party_kind
    when "guest"
      errors.add(:booking_guest, "must be present for guest billing parties") if booking_guest_id.blank?
      errors.add(:hotel_corporate_account, "must be blank for guest billing parties") if hotel_corporate_account_id.present?
    when "company"
      errors.add(:hotel_corporate_account, "must be present for company billing parties") if hotel_corporate_account_id.blank?
      errors.add(:booking_guest, "must be blank for company billing parties") if booking_guest_id.present?
    end
  end

  def booking_guest_belongs_to_booking
    return if booking_guest.blank? || booking_id.blank? || booking_guest.booking_id == booking_id

    errors.add(:booking_guest, "must belong to the same booking")
  end

  def hotel_corporate_account_belongs_to_hotel
    return if hotel_corporate_account.blank? || hotel_id.blank? || hotel_corporate_account.hotel_id == hotel_id

    errors.add(:hotel_corporate_account, "must belong to the same hotel")
  end
end
