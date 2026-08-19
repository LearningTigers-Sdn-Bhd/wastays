# frozen_string_literal: true

# `manage_concierge` has been named in the seed registry and handed to Front
# Desk since the concierge shipped, but it was only ever created by seeding --
# and production migrates without ever seeding. So on any property created
# before this, the permission row may simply not exist: owner and general
# manager derive their permissions from the registry and would silently skip
# it, and the first controller to enforce it would lock everyone out for a
# reason nothing logs.
#
# This creates the row if it is missing and attaches it to the roles that
# should already have had it. It is deliberately idempotent -- somewhere the
# seeds did run, this changes nothing.
class EnsureManageConciergePermission < ActiveRecord::Migration[8.1]
  NAME = "Manage Concierge"
  SLUG = "manage_concierge"

  # Owner and general manager hold whatever is in the registry, so they need
  # the row to exist. Front desk names it explicitly and is the desk that
  # actually answers guests.
  ROLE_SLUGS = %w[hotel_owner general_manager front_desk].freeze

  def up
    permission = Permission.find_or_create_by!(slug: SLUG) { |record| record.name = NAME }

    Role.where(slug: ROLE_SLUGS).find_each do |role|
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end
  end

  def down
    # Irreversible by design: the permission predates this migration on every
    # installation that was ever seeded, and dropping it would revoke access
    # this migration did not grant.
  end
end
