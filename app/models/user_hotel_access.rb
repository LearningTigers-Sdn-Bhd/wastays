class UserHotelAccess < ApplicationRecord
  ACCOUNT_MANAGEMENT_PERMISSION = "manage_account"

  belongs_to :user
  belongs_to :hotel
  belongs_to :role

  validates :user_id, uniqueness: { scope: :hotel_id }

  scope :active, -> { where(deactivated_at: nil) }
  scope :deactivated, -> { where.not(deactivated_at: nil) }
  scope :managing_account, -> {
    joins(role: :permissions).where(permissions: { slug: ACCOUNT_MANAGEMENT_PERMISSION })
  }

  # Active first, then most recently granted. Plain `deactivated_at: :asc` sorts
  # NULLs last in Postgres, which buried the working staff under the revoked ones.
  scope :in_directory_order, -> {
    order(Arel.sql("deactivated_at ASC NULLS FIRST"), created_at: :desc)
  }

  def active?
    deactivated_at.nil?
  end

  def deactivate!
    update!(deactivated_at: Time.current)
  end

  def reactivate!
    update!(deactivated_at: nil)
  end

  def manages_account?
    role.permissions.any? { |permission| permission.slug == ACCOUNT_MANAGEMENT_PERMISSION }
  end

  # Revoking or deleting the last active account manager leaves the property
  # with nobody who can restore access. Soft revocation is recoverable by the
  # platform; a permanent delete is not, so both paths refuse it.
  def sole_account_manager?
    return false unless active? && manages_account?

    hotel.user_hotel_accesses.active.managing_account.where.not(id: id).none?
  end
end
