# frozen_string_literal: true

class AddOverrideBookingRatePermission < ActiveRecord::Migration[8.1]
  NAME = "Override Booking Rate"
  SLUG = "override_booking_rate"

  # Owner and general manager derive their permissions from the whole registry,
  # so they only need the backfill below. Front desk holds an explicit list and
  # is the desk that takes the booking, so it is named here too.
  ROLE_SLUGS = %w[hotel_owner general_manager front_desk].freeze

  def up
    permission = Permission.find_or_create_by!(slug: SLUG) { |record| record.name = NAME }

    Role.where(slug: ROLE_SLUGS).find_each do |role|
      RolePermission.find_or_create_by!(role: role, permission: permission)
    end
  end

  def down
    RolePermission.joins(:permission).where(permissions: { slug: SLUG }).delete_all
    Permission.where(slug: SLUG).delete_all
  end
end
