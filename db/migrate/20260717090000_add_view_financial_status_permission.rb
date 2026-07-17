# frozen_string_literal: true

class AddViewFinancialStatusPermission < ActiveRecord::Migration[8.0]
  PERMISSION_SLUG = "view_financial_status".freeze
  ROLE_SLUGS = %w[hotel_owner general_manager front_desk].freeze

  def up
    permission = Permission.find_or_create_by!(slug: PERMISSION_SLUG) do |record|
      record.name = "View Financial Status"
    end

    Role.where(slug: ROLE_SLUGS).find_each do |role|
      RolePermission.find_or_create_by!(role:, permission:)
    end
  end

  def down
    permission = Permission.find_by(slug: PERMISSION_SLUG)
    return unless permission

    RolePermission.where(permission:).delete_all
    permission.destroy!
  end
end
