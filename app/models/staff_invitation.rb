# frozen_string_literal: true

class StaffInvitation < ApplicationRecord
  EXPIRY = 7.days

  belongs_to :account
  belongs_to :hotel
  belongs_to :role
  belongs_to :invited_by_user, class_name: "User"

  before_validation :normalize_email
  before_validation :set_defaults, on: :create

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :hotel_belongs_to_account
  validate :role_belongs_to_account

  scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.find_by_token(token)
    find_by(token_digest: digest(token))
  end

  def self.generate_token
    SecureRandom.urlsafe_base64(32)
  end

  def accepted?
    accepted_at.present?
  end

  def expired?
    expires_at <= Time.current
  end

  def pending?
    !accepted? && !expired?
  end

  def refresh!(role:, invited_by_user:, name: nil)
    token = self.class.generate_token
    update!(
      role: role,
      invited_by_user: invited_by_user,
      name: name.presence || self.name,
      token_digest: self.class.digest(token),
      expires_at: self.class::EXPIRY.from_now
    )
    token
  end

  def accept!(user)
    with_lock do
      return if accepted?

      access = UserHotelAccess.find_or_initialize_by(user: user, hotel: hotel)
      access.role = role
      access.deactivated_at = nil
      access.save!

      update!(accepted_at: Time.current)
    end
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def set_defaults
    self.account ||= hotel&.account
    self.expires_at ||= EXPIRY.from_now
    self.token_digest ||= self.class.digest(self.class.generate_token)
  end

  def hotel_belongs_to_account
    return if account.blank? || hotel.blank? || hotel.account_id == account_id

    errors.add(:hotel, "must belong to the invitation account")
  end

  def role_belongs_to_account
    return if account.blank? || role.blank? || role.account_id == account_id

    errors.add(:role, "must belong to the invitation account")
  end
end
