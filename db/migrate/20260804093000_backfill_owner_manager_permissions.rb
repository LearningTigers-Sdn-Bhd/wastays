# frozen_string_literal: true

# The "Hotel Owner" role is supposed to hold every permission that exists
# (seed_account_roles.rb derives it by exclusion), but several core
# permissions (reports, audit logs, night audit, requests, housekeeping
# tasks) were only ever created via db/seeds.rb rather than a migration.
# Accounts created before those seed rows existed never got them granted,
# unlike other permissions added after launch which shipped with a
# backfill migration. This tops up every existing hotel_owner/general_manager
# role so they match what a superadmin already sees.
class BackfillOwnerManagerPermissions < ActiveRecord::Migration[8.0]
  PERMISSIONS = {
    "view_reports" => "View Reports",
    "view_audit_logs" => "View Audit Logs",
    "manage_night_audit" => "Manage Night Audit",
    "manage_requests" => "Manage Requests",
    "perform_housekeeping_tasks" => "Perform Housekeeping Tasks",
    "dispatch_housekeeping_tasks" => "Dispatch Housekeeping Tasks"
  }.freeze

  GENERAL_MANAGER_EXCLUSIONS = %w[manage_account].freeze

  def up
    permissions = PERMISSIONS.map do |slug, name|
      Permission.find_or_create_by!(slug: slug) { |record| record.name = name }
    end

    Role.where(slug: "hotel_owner").find_each do |role|
      permissions.each { |permission| RolePermission.find_or_create_by!(role:, permission:) }
    end

    Role.where(slug: "general_manager").find_each do |role|
      permissions.reject { |p| GENERAL_MANAGER_EXCLUSIONS.include?(p.slug) }.each do |permission|
        RolePermission.find_or_create_by!(role:, permission:)
      end
    end
  end

  def down
    # Intentionally a no-op: this migration only grants pre-existing,
    # already-in-use permission slugs to roles that should have always had
    # them. Reverting would strip access other permissions may now depend on.
  end
end
