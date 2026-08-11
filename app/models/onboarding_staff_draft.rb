# frozen_string_literal: true

class OnboardingStaffDraft < ApplicationRecord
  belongs_to :hotel
  belongs_to :role

  before_validation :normalize_attributes

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { scope: :hotel_id, case_sensitive: false }
  validate :role_belongs_to_hotel_account
  validate :role_is_seeded_preset

  private

  def normalize_attributes
    self.name = name.to_s.strip.presence
    self.email = email.to_s.strip.downcase
  end

  def role_belongs_to_hotel_account
    return if hotel.blank? || role.blank? || role.account_id == hotel.account_id

    errors.add(:role, "must belong to the property's account")
  end

  def role_is_seeded_preset
    return if role.blank? || role.slug.in?(Onboarding::ConfirmRolePresets::PRESET_SLUGS)

    errors.add(:role, "must be one of the seeded presets")
  end
end
