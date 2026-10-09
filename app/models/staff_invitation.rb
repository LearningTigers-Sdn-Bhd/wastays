# frozen_string_literal: true

class StaffInvitation < Invitation
  PARTNER_INVITATION_ERROR = "This account cannot be invited as hotel staff."

  default_scope { staff }

  scope :excluding_partners, -> { where.not(email: User.super_agents.select(:email)) }

  before_validation { self.kind = "staff" }

  validates :role, presence: true
  validate :role_belongs_to_account
  validate :recipient_is_not_partner

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

      if user.super_agent? || User.super_agents.exists?(email: email)
        errors.add(:base, PARTNER_INVITATION_ERROR)
        raise ActiveRecord::RecordInvalid, self
      end

      access = UserHotelAccess.find_or_initialize_by(user: user, hotel: hotel)
      access.role = role
      access.deactivated_at = nil
      access.save!

      update!(accepted_at: Time.current)
    end
  end

  private

  def recipient_is_not_partner
    errors.add(:base, PARTNER_INVITATION_ERROR) if User.super_agents.exists?(email: email)
  end

  def role_belongs_to_account
    return if account.blank? || role.blank? || role.account_id == account_id

    errors.add(:role, "must belong to the invitation account")
  end
end
