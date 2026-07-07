# frozen_string_literal: true

class Guest < ApplicationRecord
  belongs_to :created_by_hotel, class_name: "Hotel", optional: true
  has_many :booking_guests, dependent: :destroy
  has_many :bookings, through: :booking_guests
  has_many :prospects, dependent: :nullify

  has_one_attached :id_front
  has_one_attached :id_back

  encrypts :email, deterministic: true
  encrypts :phone, deterministic: true
  encrypts :government_id, deterministic: true

  OTP_EXPIRY = 10.minutes
  MAGIC_LINK_EXPIRY = 24.hours
  OTP_LENGTH = 6
  RESEND_COOLDOWN = 2.minutes

  validates :name, presence: true
  validates :country, presence: true
  validates :gender, inclusion: { in: %w[male female other], message: "must be male, female, or other" }, allow_blank: true
  validates :document_type, inclusion: { in: %w[ic passport], message: "must be IC or passport" }, allow_blank: true
  validate :date_of_birth_must_be_before_today, if: :date_of_birth?
  validate :date_of_birth_required_for_passport_guests
  validate :date_of_birth_required_for_reporting_guests

  GENDERS = %w[male female other].freeze
  DOCUMENT_TYPES = %w[ic passport].freeze

  scope :kept, -> { where(discarded_at: nil) }
  scope :discarded, -> { where.not(discarded_at: nil) }

  before_validation :normalize_guest_data
  before_validation :populate_date_of_birth_from_malaysian_ic

  after_update :propagate_vip_status, if: :saved_change_to_vip?

  def self.blacklisted?(email: nil, name: nil)
    return false if email.blank? && name.blank?

    query = Guest.where(blacklisted: true)
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

  def repeat?
    bookings.where(status: "completed").exists? && bookings.count > 1
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

  def magic_link_on_cooldown?
    magic_token_expires_at.present? && magic_token_expires_at > (MAGIC_LINK_EXPIRY - RESEND_COOLDOWN).from_now
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

  def generate_magic_token!
    token = SecureRandom.urlsafe_base64(32)
    update!(
      magic_token_digest: Digest::SHA256.hexdigest(token),
      magic_token_expires_at: MAGIC_LINK_EXPIRY.from_now
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

  private

  def normalize_guest_data
    self.email = email&.downcase&.strip
    self.government_id = government_id&.downcase&.strip
    self.gender = gender&.downcase
    self.document_type = document_type&.downcase
    self.country = normalized_country
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
    return unless passport_guest?

    errors.add(:date_of_birth, "is required for passport guests")
  end

  def date_of_birth_required_for_reporting_guests
    return unless date_of_birth.blank?
    return unless non_malaysian_guest?

    errors.add(:date_of_birth, date_of_birth_required_message)
  end

  def malaysian_ic_guest?
    country == "Malaysia" && document_type == "ic"
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

  def propagate_vip_status
    bookings.update_all(vip: vip)
  end
end
