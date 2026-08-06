# frozen_string_literal: true

# `manage_housekeeping_tasks` conflated two different jobs: performing a
# housekeeping task and dispatching one to somebody else. Split it so a
# housekeeper can take work without being able to hand work to a colleague.
#
# Every role that held the old permission gets `perform_housekeeping_tasks`.
# It also gets `dispatch_housekeeping_tasks` unless it is a housekeeper role,
# which is the only seeded role meant to be perform-only.
class SplitHousekeepingTaskPermissions < ActiveRecord::Migration[8.0]
  OLD_SLUG = "manage_housekeeping_tasks"
  PERFORM = { slug: "perform_housekeeping_tasks", name: "Perform Housekeeping Tasks" }.freeze
  DISPATCH = { slug: "dispatch_housekeeping_tasks", name: "Dispatch Housekeeping Tasks" }.freeze

  def up
    perform_id = create_permission(**PERFORM)
    dispatch_id = create_permission(**DISPATCH)
    old_id = permission_id(OLD_SLUG)
    return if old_id.nil?

    holders = roles_holding(old_id)
    grant(perform_id, holders)
    grant(dispatch_id, holders - housekeeper_role_ids)

    drop_permissions([ old_id ])
  end

  def down
    old_id = create_permission(slug: OLD_SLUG, name: "Manage Housekeeping Tasks")
    perform_id = permission_id(PERFORM[:slug])
    dispatch_id = permission_id(DISPATCH[:slug])

    grant(old_id, roles_holding(perform_id) | roles_holding(dispatch_id))

    drop_permissions([ perform_id, dispatch_id ])
  end

  private

  def create_permission(slug:, name:)
    execute <<~SQL.squish
      INSERT INTO permissions (slug, name, created_at, updated_at)
      VALUES (#{quote(slug)}, #{quote(name)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      ON CONFLICT (slug) DO NOTHING
    SQL
    permission_id(slug)
  end

  def permission_id(slug)
    select_value("SELECT id FROM permissions WHERE slug = #{quote(slug)}")
  end

  def roles_holding(permission_id)
    return [] if permission_id.nil?

    select_values("SELECT role_id FROM role_permissions WHERE permission_id = #{quote(permission_id)}")
  end

  def housekeeper_role_ids
    select_values("SELECT id FROM roles WHERE slug = 'housekeeper'")
  end

  def grant(permission_id, role_ids)
    return if permission_id.nil? || role_ids.empty?

    values = role_ids.map { |role_id| "(#{quote(role_id)}, #{quote(permission_id)}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)" }
    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      VALUES #{values.join(', ')}
    SQL
  end

  def drop_permissions(ids)
    ids = ids.compact
    return if ids.empty?

    list = ids.map { |id| quote(id) }.join(", ")
    execute "DELETE FROM role_permissions WHERE permission_id IN (#{list})"
    execute "DELETE FROM permissions WHERE id IN (#{list})"
  end
end
