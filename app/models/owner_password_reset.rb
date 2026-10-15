# frozen_string_literal: true

class OwnerPasswordReset < ApplicationRecord
  EXPIRY = 30.minutes

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  def self.issue!(user)
    token = SecureRandom.urlsafe_base64(32)
    user.with_lock do
      user.owner_password_resets.delete_all
      create!(user:, token_digest: Digest::SHA256.hexdigest(token), expires_at: EXPIRY.from_now)
    end
    token
  end

  def self.find_valid(token)
    return if token.blank?

    find_by(token_digest: Digest::SHA256.hexdigest(token))&.then do |reset|
      reset if reset.consumed_at.nil? && reset.expires_at.future?
    end
  end
end
