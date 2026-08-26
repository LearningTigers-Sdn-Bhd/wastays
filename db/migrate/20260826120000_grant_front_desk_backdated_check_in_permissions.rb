# frozen_string_literal: true

# A check-in on a closed business date posts the accommodation catch-up charge
# onto a locked date, so it needs both folio permissions on top of
# manage_bookings. Without them the sheet offers the override switch and a
# reason box, then refuses the save with a folio error the desk cannot act on.
#
# AddOverrideFinancialDateLockPermission gave the lock override to owners and
# general managers only. This widens it to the front desk, which also gives
# them the force-close and force-roll controls that read the same permission.
class GrantFrontDeskBackdatedCheckInPermissions < ActiveRecord::Migration[8.0]
  PERMISSION_SLUGS = %w[post_folio_charges override_financial_date_lock].freeze
  ROLE_SLUG = "front_desk"
  ADDED_SLUG = "override_financial_date_lock"

  def up
    roles = Role.where(slug: ROLE_SLUG)
    return if roles.empty?

    PERMISSION_SLUGS.each do |slug|
      permission = Permission.find_by(slug: slug)
      next if permission.nil?

      roles.find_each do |role|
        RolePermission.find_or_create_by!(role: role, permission: permission)
      end
    end
  end

  # Only the grant this migration introduced comes back out. post_folio_charges
  # was already part of the front desk template, so removing it here would take
  # away a permission this migration did not give.
  def down
    permission = Permission.find_by(slug: ADDED_SLUG)
    return if permission.nil?

    RolePermission.where(permission: permission, role: Role.where(slug: ROLE_SLUG)).delete_all
  end
end
