# frozen_string_literal: true

class AddRoomReadinessPermissions < ActiveRecord::Migration[8.0]
  PERMISSIONS = [
    [ "View Room Readiness", "view_room_readiness" ],
    [ "Manage Room Status", "manage_room_status" ],
    [ "Override Room Status Assignment", "override_room_status_assignment" ]
  ].freeze

  ROLE_PERMISSION_SLUGS = {
    "hotel_owner" => %w[view_room_readiness manage_room_status override_room_status_assignment],
    "general_manager" => %w[view_room_readiness manage_room_status override_room_status_assignment],
    "front_desk" => %w[view_room_readiness],
    "reservation_staff" => %w[view_room_readiness]
  }.freeze

  def up
    PERMISSIONS.each do |name, slug|
      Permission.find_or_create_by!(slug: slug) do |permission|
        permission.name = name
      end
    end

    Role.where(slug: ROLE_PERMISSION_SLUGS.keys).find_each do |role|
      ROLE_PERMISSION_SLUGS.fetch(role.slug, []).each do |permission_slug|
        permission = Permission.find_by!(slug: permission_slug)
        RolePermission.find_or_create_by!(role: role, permission: permission)
      end
    end
  end

  def down
    slugs = PERMISSIONS.map(&:last)
    RolePermission.joins(:permission).where(permissions: { slug: slugs }).delete_all
    Permission.where(slug: slugs).delete_all
  end
end
