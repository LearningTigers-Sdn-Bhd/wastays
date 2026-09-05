# frozen_string_literal: true

class Guest < ApplicationRecord
  attr_accessor :lhdn_document_type
  belongs_to :created_by_hotel, class_name: "Hotel", optional: true
  has_many :booking_guests, dependent: :destroy
  has_many :bookings, through: :booking_guests
  has_many :prospects, dependent: :nullify

  has_one_attached :id_front
  has_one_attached :id_back

  encrypts :email, deterministic: true
  encrypts :phone, deterministic: true
  encrypts :government_id, deterministic: true
  encrypts :passport_number, deterministic: true

  OTP_EXPIRY = 10.minutes
  MAGIC_LINK_EXPIRY = 24.hours
  OTP_LENGTH = 6
  RESEND_COOLDOWN = 2.minutes

  validates :name, presence: true
  validates :country, presence: true
  validates :gender, inclusion: { in: %w[male female other], message: "must be male, female, or other" }, allow_blank: true
  validates :document_type, inclusion: { in: %w[malaysian_nric national_id passport], message: "must be MyKad, national ID, or passport" }, allow_blank: true
  validate :date_of_birth_must_be_before_today, if: :date_of_birth?
  validate :date_of_birth_required_for_passport_guests
  validate :date_of_birth_required_for_reporting_guests

  GENDERS = %w[male female other].freeze
  DOCUMENT_TYPES = %w[malaysian_nric national_id passport].freeze

  scope :kept, -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }

  # A guest record is shared across properties. A property may read it once the
  # guest has booked there, or once that property created the record.
  scope :for_hotel, ->(hotel) {
    left_outer_joins(:bookings)
      .where("guests.created_by_hotel_id = :hotel_id OR bookings.hotel_id = :hotel_id", hotel_id: hotel.id)
      .distinct
  }

  before_validation :normalize_guest_data
  before_validation :populate_date_of_birth_from_malaysian_ic

  after_update :propagate_vip_status, if: :vip_scope_changed?

  def self.blacklisted?(email: nil, name: nil, hotel: nil)
    return false if email.blank? && name.blank?

    query = Guest.where(blacklisted: true)
    if hotel
      hotel_id = hotel.is_a?(ActiveRecord::Base) ? hotel.id : hotel.to_i
      query = query.where(
        "guests.metadata @> :h_json OR (COALESCE(guests.metadata->'blacklisted_hotel_ids', '[]'::jsonb) = '[]'::jsonb AND (guests.created_by_hotel_id IS NULL OR guests.created_by_hotel_id = :h_id))",
        h_json: { blacklisted_hotel_ids: [ hotel_id ] }.to_json,
        h_id: hotel_id
      )
    end

    subqueries = []
    subqueries << query.where(email: email.strip.downcase) if email.present?
    subqueries << query.where("LOWER(name) = ?", name.strip.downcase) if name.present?

    if subqueries.size == 2
      subqueries[0].or(subqueries[1]).exists?
    elsif subqueries.size == 1
      subqueries[0].exists?
    else
      false
    end
  end

  def self.banned?(email: nil, phone: nil, name: nil, hotel: nil)
    email_clean = email.to_s.strip.downcase.presence
    phone_clean = phone.to_s.strip.presence
    name_clean = name.to_s.strip.downcase.presence

    return false if email_clean.blank? && phone_clean.blank? && name_clean.blank?

    query = Guest.where(blacklisted: true)
    if hotel
      hotel_id = hotel.is_a?(ActiveRecord::Base) ? hotel.id : hotel.to_i
      query = query.where(
        "guests.metadata @> :h_json OR (COALESCE(guests.metadata->'blacklisted_hotel_ids', '[]'::jsonb) = '[]'::jsonb AND (guests.created_by_hotel_id IS NULL OR guests.created_by_hotel_id = :h_id))",
        h_json: { blacklisted_hotel_ids: [ hotel_id ] }.to_json,
        h_id: hotel_id
      )
    end

    is_banned = false
    if email_clean.present?
      is_banned ||= query.where(email: email_clean).exists?
    end
    if !is_banned && phone_clean.present?
      is_banned ||= query.where(phone: phone_clean).exists?
    end
    if !is_banned && name_clean.present?
      is_banned ||= query.where("LOWER(name) = ?", name_clean).exists?
    end

    is_banned
  end

  def blacklisted?(hotel: nil)
    if hotel
      blacklisted_at?(hotel)
    else
      super()
    end
  end

  def blacklisted_at?(hotel)
    return false unless hotel
    hotel_id = hotel.is_a?(ActiveRecord::Base) ? hotel.id : hotel.to_i

    if metadata&.dig("blacklisted_hotel_ids").present?
      metadata["blacklisted_hotel_ids"].include?(hotel_id)
    else
      self[:blacklisted] && (created_by_hotel_id.nil? || created_by_hotel_id == hotel_id)
    end
  end

  def blacklist_detail(hotel)
    return nil unless hotel
    hotel_id = hotel.is_a?(ActiveRecord::Base) ? hotel.id : hotel.to_i
    metadata&.dig("blacklist_details", hotel_id.to_s)
  end

  # VIP is set per property, the same way a blacklist is. The property ids live
  # in `metadata["vip_hotel_ids"]` and the `vip` column stays true while any
  # property still holds the flag.
  def vip?(hotel: nil)
    if hotel
      vip_at?(hotel)
    else
      super()
    end
  end

  def vip_at?(hotel)
    return false unless hotel
    hotel_id = hotel.is_a?(ActiveRecord::Base) ? hotel.id : hotel.to_i

    if metadata&.dig("vip_hotel_ids").present?
      metadata["vip_hotel_ids"].include?(hotel_id)
    else
      self[:vip] && (created_by_hotel_id.nil? || created_by_hotel_id == hotel_id)
    end
  end

  def repeat?
    if bookings.loaded?
      bookings.any? { |b| b.status == "completed" } && bookings.size > 1
    else
      bookings.where(status: "completed").exists? && bookings.count > 1
    end
  end

  def discard
    update(discarded_at: Time.current)
  end

  def discard!
    update!(discarded_at: Time.current)
  end

  def undiscard
    update(discarded_at: nil)
  end

  def discarded?
    discarded_at.present?
  end

  def kept?
    discarded_at.nil?
  end

  def otp_on_cooldown?
    otp_sent_at.present? && otp_sent_at > RESEND_COOLDOWN.ago
  end

  def magic_link_on_cooldown?(now: Time.current)
    magic_token_expires_at.present? && magic_token_expires_at > now + MAGIC_LINK_EXPIRY - RESEND_COOLDOWN
  end

  def generate_otp!
    code = SecureRandom.random_number(10**OTP_LENGTH).to_s.rjust(OTP_LENGTH, "0")
    update!(
      otp_code_digest: BCrypt::Password.create(code),
      otp_sent_at: Time.current
    )
    code
  end

  def verify_otp(code)
    return false if otp_code_digest.blank? || otp_sent_at.blank?
    return false if otp_sent_at < OTP_EXPIRY.ago
    BCrypt::Password.new(otp_code_digest) == code
  end

  def generate_magic_token!(now: Time.current)
    token = SecureRandom.urlsafe_base64(32)
    update!(
      magic_token_digest: Digest::SHA256.hexdigest(token),
      magic_token_expires_at: now + MAGIC_LINK_EXPIRY
    )
    token
  end

  def verify_magic_token(token)
    return false if magic_token_digest.blank? || magic_token_expires_at.blank?
    return false if magic_token_expires_at < Time.current
    Digest::SHA256.hexdigest(token) == magic_token_digest
  end

  def consume_otp!
    update!(otp_code_digest: nil, otp_sent_at: nil, last_signed_in_at: Time.current)
  end

  def consume_magic_token!
    update!(magic_token_digest: nil, magic_token_expires_at: nil, last_signed_in_at: Time.current)
  end

  def normalized_country
    country&.split&.map(&:capitalize)&.join(" ")
  end

  def normalized_city
    city&.split&.map(&:capitalize)&.join(" ")
  end

  def identity_document_type
    document_type
  end

  def identity_document_number
    safely_read_encrypted(:government_id)
  end

  # LHDN accepts a MyKad or a passport only. A guest who holds a foreign
  # national identity card must also give a passport number.
  def lhdn_passport_required?
    document_type == "national_id"
  end

  def identity_document_label
    case document_type
    when "malaysian_nric" then "MyKad"
    when "national_id" then "National identity card"
    when "passport" then "Passport"
    else "Identity document"
    end
  end

  # Guards against ActiveRecord::Encryption::Errors::Decryption for guest
  # records whose encrypted attributes were written under a since-rotated or
  # mismatched encryption key. Callers get nil instead of a raised error, so a
  # single unreadable field never blocks a booking confirmation that already
  # collected fresh plaintext data from the guest.
  def safely_read_encrypted(attribute)
    public_send(attribute)
  rescue ActiveRecord::Encryption::Errors::Decryption => e
    Rails.logger.warn("[Guest##{id}] failed to decrypt #{attribute}: #{e.message}")
    nil
  end

  private

  def normalize_guest_data
    self.email = email&.downcase&.strip
    self.government_id = government_id&.downcase&.strip
    self.passport_number = passport_number&.downcase&.strip
    self.gender = gender&.downcase
    normalized_document_type = GuestIdentityDocuments::NormalizeType.call(value: document_type, country: country)
    self.document_type = normalized_document_type || document_type&.downcase
    self.city = normalized_city
    self.country = normalized_country
    self.passport_issuing_country_code = passport_number.present? ? GuestIdentityDocuments::NormalizeType.country_code(country) : nil
  end

  def populate_date_of_birth_from_malaysian_ic
    return if date_of_birth.present?
    return unless malaysian_ic_guest?

    self.date_of_birth = Guests::MalaysianIcDateOfBirthParser.parse(government_id)
  end

  def date_of_birth_must_be_before_today
    errors.add(:date_of_birth, "must be in the past") unless date_of_birth < Date.current
  end

  def date_of_birth_required_for_passport_guests
    return unless date_of_birth.blank?
    return if incomplete_channel_manager_profile?
    return unless passport_guest?

    errors.add(:date_of_birth, "is required for passport guests")
  end

  def date_of_birth_required_for_reporting_guests
    return unless date_of_birth.blank?
    return if incomplete_channel_manager_profile?
    return unless non_malaysian_guest?

    errors.add(:date_of_birth, date_of_birth_required_message)
  end

  def incomplete_channel_manager_profile?
    metadata.is_a?(Hash) &&
      metadata["profile_source"] == "channel_manager" &&
      metadata["profile_incomplete"] == true
  end

  def malaysian_ic_guest?
    country == "Malaysia" && document_type == "malaysian_nric"
  end

  def passport_guest?
    document_type == "passport"
  end

  def non_malaysian_guest?
    country.present? && country != "Malaysia"
  end

  def date_of_birth_required_message
    "is required for passport guests"
  end

  # Fires when the VIP column moves, or when the set of properties holding the
  # flag moves. A blacklist write also touches metadata, so compare the VIP key
  # rather than the whole column.
  def vip_scope_changed?
    return true if saved_change_to_vip?
    return false unless saved_change_to_metadata?

    before, after = saved_change_to_metadata
    before&.dig("vip_hotel_ids") != after&.dig("vip_hotel_ids")
  end

  def propagate_vip_status
    hotel_ids = metadata&.dig("vip_hotel_ids")

    # Records written before the per-property flag existed carry the column
    # alone. Guest#vip_at? reads them at every property, so propagate the same.
    return bookings.update_all(vip: self[:vip]) if hotel_ids.blank?

    bookings.where(hotel_id: hotel_ids).update_all(vip: true)
    bookings.where.not(hotel_id: hotel_ids).update_all(vip: false)
  end
end
