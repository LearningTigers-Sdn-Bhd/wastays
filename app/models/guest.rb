# frozen_string_literal: true

class Guest < ApplicationRecord
  belongs_to :created_by_hotel, class_name: "Hotel", optional: true
  has_many :booking_guests, dependent: :destroy
  has_many :bookings, through: :booking_guests

  encrypts :email, deterministic: true
  encrypts :phone, deterministic: true
  encrypts :government_id

  OTP_EXPIRY = 10.minutes
  MAGIC_LINK_EXPIRY = 24.hours
  OTP_LENGTH = 6
  RESEND_COOLDOWN = 2.minutes

  validates :name, presence: true
  validates :country, presence: true
  validates :gender, inclusion: { in: %w[male female other], message: "must be male, female, or other" }, allow_blank: true
  validates :document_type, inclusion: { in: %w[ic passport], message: "must be IC or passport" }, allow_blank: true
  validates :government_id, presence: true, allow_blank: true

  GENDERS = %w[male female other].freeze
  DOCUMENT_TYPES = %w[ic passport].freeze

  before_validation :normalize_guest_data

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
end
