# frozen_string_literal: true

# An OTA extranet login the owner hands over during setup, so the WAStays team
# can connect that channel to the property's channel manager after approval.
#
# Onboarding only collects these. Nothing here talks to Channex or to the OTA —
# connecting is admin work that happens later, against records that outlive the
# onboarding run, which is why these hang off the hotel rather than living in an
# onboarding-only drafts table like OnboardingCorporateDraft.
#
# The credentials belong to the hotel but are not readable back in the hotel
# portal: the owner types a password once and can replace it, never retrieve it.
# The onboarding section never renders the stored value into a field, which is
# what makes that true — there is no other portal path to these rows yet.
class HotelOtaCredential < ApplicationRecord
  include HotelScopable

  STATUSES = %w[pending processed].freeze

  encrypts :username
  encrypts :password

  before_validation :normalize_attributes

  validates :channel_name, presence: true,
                           uniqueness: { scope: :hotel_id, case_sensitive: false,
                                         message: "already has credentials for this property" }
  validates :status, inclusion: { in: STATUSES }
  validates :market_manager_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :ordered, -> { order(:created_at, :id) }
  scope :pending, -> { where(status: "pending") }

  def processed? = status == "processed"

  # What the owner is shown in place of the stored password. The value itself
  # never reaches the browser again once saved.
  def password_saved? = password.present?

  private

  def normalize_attributes
    self.channel_name = channel_name.to_s.strip.presence
    self.property_code = property_code.to_s.strip.presence
    self.username = username.to_s.strip.presence
    self.market_manager_name = market_manager_name.to_s.strip.presence
    self.market_manager_phone = market_manager_phone.to_s.strip.presence
    self.market_manager_email = market_manager_email.to_s.strip.downcase.presence
  end
end
