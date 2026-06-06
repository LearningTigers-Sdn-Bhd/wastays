# frozen_string_literal: true

class AddOverrideFinancialDateLockPermission < ActiveRecord::Migration[8.0]
  PERMISSION_NAME = "Override Financial Date Lock".freeze
  PERMISSION_SLUG = "override_financial_date_lock".freeze
  ROLE_SLUGS = %w[hotel_owner general_manager].freeze

  def up
    permission = Permission.find_or_create_by!(slug: PERMISSION_SLUG) do |record|
      record.name = PERMISSION_NAME
    end

    Role.where(slug: ROLE_SLUGS).find_each do |role|
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end
  end

  def down
    permission = Permission.find_by(slug: PERMISSION_SLUG)
    return unless permission

    RolePermission.where(permission: permission).delete_all
    permission.destroy!
  end
end
