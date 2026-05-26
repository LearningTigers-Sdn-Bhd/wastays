# frozen_string_literal: true

module StaffAssignableRoles
  extend ActiveSupport::Concern

  private

  def assignable_roles
    @assignable_roles ||= current_hotel.account.roles.includes(:permissions).order(:name).select do |role|
      role.permissions.none? { |permission| permission.slug == "manage_account" } || current_user.has_permission?("manage_account")
    end
  end

  def assignable_role(role_id)
    assignable_roles.find { |role| role.id.to_s == role_id.to_s }
  end
end
