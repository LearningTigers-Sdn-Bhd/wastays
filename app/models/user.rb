class User < ApplicationRecord
  include AccountScopable

  DEFAULT_TIME_ZONE = "Kuala Lumpur".freeze
  ROLES = %w[superadmin admin hotel_staff salesperson corporate].freeze

  has_secure_password

  has_many :user_hotel_accesses, dependent: :destroy
  has_many :active_user_hotel_accesses, -> { active }, class_name: "UserHotelAccess"
  has_many :hotels, through: :active_user_hotel_accesses
  has_many :hotel_roles, through: :active_user_hotel_accesses, source: :role
  has_many :performed_night_audits, class_name: "NightAudit", foreign_key: :performed_by_user_id, dependent: :nullify
  has_many :sent_staff_invitations, class_name: "StaffInvitation", foreign_key: :invited_by_user_id, dependent: :restrict_with_error
  has_many :sent_corporate_invitations, class_name: "CorporateInvitation", foreign_key: :invited_by_user_id, dependent: :restrict_with_error
  has_many :channel_settlement_receipts, foreign_key: :recorded_by_id, dependent: :restrict_with_error
  has_many :assigned_room_statuses, class_name: "RoomStatus", foreign_key: :assigned_to_id, dependent: :nullify,
                                    inverse_of: :assigned_to

  has_many :assigned_hotels, class_name: "Hotel", foreign_key: "salesperson_id", dependent: :nullify

  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles

  validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
  validates :time_zone, inclusion: { in: ActiveSupport::TimeZone.all.map(&:name) }
  validates :account_id, uniqueness: true, if: :corporate?
  validate :role_matches_account_kind

  before_validation :normalize_email
  before_validation :assign_default_time_zone

  def superadmin?
    role == "superadmin"
  end

  def admin?
    role == "admin"
  end

  def corporate?
    role == "corporate"
  end

  def has_permission?(permission_slug, hotel: nil)
    return true if superadmin?

    if hotel
      # Check hotel-specific permissions
      access = user_hotel_accesses.active.find_by(hotel: hotel)
      return false unless access
      access.role.permissions.exists?(slug: permission_slug)
    else
      # Check account-level permissions
      roles.joins(:permissions).where(permissions: { slug: permission_slug }).exists?
    end
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def assign_default_time_zone
    self.time_zone = DEFAULT_TIME_ZONE if time_zone.blank?
  end

  def role_matches_account_kind
    return if account.blank?
    return if corporate? && account.corporate?
    return if !corporate? && account.hotel?

    errors.add(:account, corporate? ? "must be a corporate account" : "must be a hotel account")
  end
end
