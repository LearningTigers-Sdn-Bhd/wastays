# frozen_string_literal: true

class Invitation < ApplicationRecord
  EXPIRY = 7.days

  belongs_to :account
  belongs_to :hotel
  belongs_to :role, optional: true
  belongs_to :invited_by_user, class_name: "User"

  enum :kind, { staff: "staff", corporate: "corporate" }, validate: true

  before_validation :normalize_email
  before_validation :set_defaults, on: :create

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :hotel_belongs_to_account

  scope :unaccepted, -> { where(accepted_at: nil) }
  scope :pending, -> { unaccepted.where("expires_at > ?", Time.current) }
  scope :expired, -> { unaccepted.where("expires_at <= ?", Time.current) }
  # Created during onboarding with the send switch off: a real invitation that
  # nobody has been told about yet.
  scope :held, -> { unaccepted.where(last_sent_at: nil) }
  # What the portal lists. A held invitation has no meaningful expiry — its
  # seven days have not started — so excluding it the way `pending` does would
  # quietly drop the person a week after the owner listed them, which is the
  # opposite of holding them for later.
  scope :listable, -> { unaccepted.where("expires_at > ? OR last_sent_at IS NULL", Time.current) }

  # An invitation exists from the moment the property lists the person; being
  # emailed is a separate event, so "sent" cannot be inferred from creation.
  def sent? = last_sent_at.present?
  def held? = !sent? && !accepted?

  # An unsent invitation's expiry is meaningless — the seven days should run
  # from when the person could first act on it, not from when the owner typed
  # their address. `refresh!` restarts the clock, so sending is what makes the
  # window real.
  def mark_sent!(now = Time.current) = update!(last_sent_at: now)

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

  def rotate_token!
    token = self.class.generate_token
    update!(
      token_digest: self.class.digest(token),
      expires_at: self.class::EXPIRY.from_now
    )
    token
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
end
