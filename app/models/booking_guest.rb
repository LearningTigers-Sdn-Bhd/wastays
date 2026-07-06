class BookingGuest < ApplicationRecord
  ROLES = %w[primary additional].freeze

  belongs_to :booking
  belongs_to :guest
  has_one :booking_billing_party, dependent: :restrict_with_error

  encrypts :email_snapshot, deterministic: true
  encrypts :phone_snapshot, deterministic: true
  encrypts :government_id_snapshot, deterministic: true

  validates :is_primary, inclusion: { in: [ true, false ] }
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :guest_id, uniqueness: { scope: :booking_id }
  validates :role, uniqueness: {
    scope: :booking_id,
    conditions: -> { where(role: "primary") }
  }, if: :primary?
  before_validation :synchronize_role
  before_validation :capture_guest_snapshot, on: :create
  after_create :ensure_guest_billing_party
  after_commit :sync_booking_vip_status, on: [ :create, :update ]

  def primary?
    role == "primary"
  end

  private

  def synchronize_role
    return if is_primary.nil?

    if will_save_change_to_is_primary?
      self.role = is_primary == true ? "primary" : "additional"
    else
      self.is_primary = role == "primary"
    end
  end

  def capture_guest_snapshot
    return if guest.blank?

    self.name_snapshot ||= guest.name
    self.email_snapshot ||= guest.email
    self.phone_snapshot ||= guest.phone
    self.government_id_snapshot ||= guest.government_id
    self.gender_snapshot ||= guest.gender
    self.country_snapshot ||= guest.country
    self.document_type_snapshot ||= guest.document_type
    self.date_of_birth_snapshot ||= guest.date_of_birth
  end

  def ensure_guest_billing_party
    BookingBillingParties::EnsureForBooking.call(booking: booking)
  end

  def sync_booking_vip_status
    if guest.vip?
      booking.update!(vip: true)
    end
  end
end
