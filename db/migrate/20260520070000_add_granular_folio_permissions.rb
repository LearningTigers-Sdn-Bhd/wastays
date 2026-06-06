# frozen_string_literal: true

class AddGranularFolioPermissions < ActiveRecord::Migration[8.0]
  LEGACY_PERMISSION_SLUG = "post_folio_transactions".freeze

  PERMISSIONS = {
    "post_folio_charges" => "Post Folio Charges",
    "post_folio_payments" => "Post Folio Payments",
    "execute_folio_refunds" => "Execute Folio Refunds",
    "post_folio_adjustments" => "Post Folio Adjustments",
    "post_folio_corrections" => "Post Folio Corrections",
    "post_folio_write_offs" => "Post Folio Write-Offs"
  }.freeze

  ROLE_PERMISSION_SLUGS = {
    "hotel_owner" => PERMISSIONS.keys,
    "general_manager" => PERMISSIONS.keys,
    "front_desk" => %w[post_folio_charges post_folio_payments]
  }.freeze

  def up
    permissions_by_slug = PERMISSIONS.to_h do |slug, name|
      permission = Permission.find_or_create_by!(slug: slug) do |record|
        record.name = name
      end
      [ slug, permission ]
    end

    ROLE_PERMISSION_SLUGS.each do |role_slug, permission_slugs|
      Role.where(slug: role_slug).find_each do |role|
        permission_slugs.each do |permission_slug|
          RolePermission.find_or_create_by!(role: role, permission: permissions_by_slug.fetch(permission_slug))
        end
      end
    end

    remove_legacy_permission!
  end

  def down
    permissions = Permission.where(slug: PERMISSIONS.keys)
    RolePermission.where(permission: permissions).delete_all
    permissions.destroy_all

    restore_legacy_permission!
  end

  private

  def remove_legacy_permission!
    legacy_permission = Permission.find_by(slug: LEGACY_PERMISSION_SLUG)
    return unless legacy_permission

    RolePermission.where(permission: legacy_permission).delete_all
    legacy_permission.destroy!
  end

  def restore_legacy_permission!
    legacy_permission = Permission.find_or_create_by!(slug: LEGACY_PERMISSION_SLUG) do |record|
      record.name = "Post Folio Transactions"
    end

    %w[hotel_owner general_manager front_desk].each do |role_slug|
      Role.where(slug: role_slug).find_each do |role|
        RolePermission.find_or_create_by!(role: role, permission: legacy_permission)
      end
    end
  end
end
