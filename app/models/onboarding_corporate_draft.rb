# frozen_string_literal: true

# A corporate account an owner wants invited, held until the property is
# approved. CorporateInvitations::CreateService emails as it creates, so
# onboarding cannot use it during setup; these rows are what submission turns
# into real invitations.
#
# The validations deliberately mirror CorporateInvitation's, so a draft that
# saves here will not be rejected at delivery — the owner finds out now, while
# they can fix it, rather than after submission.
class OnboardingCorporateDraft < ApplicationRecord
  belongs_to :hotel
  belongs_to :invitation, optional: true

  before_validation :normalize_attributes

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP },
                    uniqueness: { scope: :hotel_id, case_sensitive: false }
  validates :account_type, inclusion: { in: HotelCorporateAccount::ACCOUNT_TYPES }
  validates :relationship_type, inclusion: { in: %w[standard direct_bill] }
  validates :credit_currency, presence: true, inclusion: { in: CurrencyCatalog.codes }
  validates :credit_limit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :payment_terms_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :email_is_free_for_this_property

  scope :undelivered, -> { where(invitation_id: nil) }

  def delivered? = invitation_id.present?

  private

  def normalize_attributes
    self.email = email.to_s.strip.downcase
    self.company_name = company_name.to_s.strip.presence
    self.credit_currency = credit_currency.presence || hotel&.default_currency
  end

  # `invitations` carries a unique index on (hotel_id, email) for everything not
  # yet accepted, and it is not scoped by kind — so a corporate address that
  # collides with a pending staff invitation, or with a staff member queued in
  # the same onboarding run, would fail at delivery rather than here.
  def email_is_free_for_this_property
    return if hotel.blank? || email.blank?

    if hotel.invitations.unaccepted.where("LOWER(email) = ?", email).where.not(id: invitation_id).exists?
      errors.add(:email, "already has a pending invitation for this property")
    elsif hotel.onboarding_staff_drafts.where("LOWER(email) = ?", email).exists?
      errors.add(:email, "is already queued as a staff member")
    end
  end
end
