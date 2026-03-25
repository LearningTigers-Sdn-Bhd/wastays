class User < ApplicationRecord
  include AccountScopable

  has_secure_password

  has_many :user_hotel_accesses, dependent: :destroy
  has_many :hotels, through: :user_hotel_accesses
  has_many :hotel_roles, through: :user_hotel_accesses, source: :role

  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true
  validates :role, presence: true

  ROLES = %w[superadmin admin hotel_staff].freeze

  def superadmin?
    role == "superadmin"
  end

  def admin?
    role == "admin"
  end

  def has_permission?(permission_slug, hotel: nil)
    return true if superadmin?

    if hotel
      # Check hotel-specific permissions
      access = user_hotel_accesses.find_by(hotel: hotel)
      return false unless access
      access.role.permissions.exists?(slug: permission_slug)
    else
      # Check account-level permissions
      roles.joins(:permissions).where(permissions: { slug: permission_slug }).exists?
    end
  end
end
