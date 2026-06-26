# frozen_string_literal: true

class StaffInvitation < Invitation
  default_scope { staff }

  before_validation { self.kind = "staff" }

  validates :role, presence: true
  validate :role_belongs_to_account

  def refresh!(role:, invited_by_user:, name: nil)
    token = rotate_token!
    update!(
      role: role,
      invited_by_user: invited_by_user,
      name: name.presence || self.name
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

  def role_belongs_to_account
    return if account.blank? || role.blank? || role.account_id == account_id

    errors.add(:role, "must belong to the invitation account")
  end
end
