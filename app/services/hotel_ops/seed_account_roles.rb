# frozen_string_literal: true

module HotelOps
  class SeedAccountRoles
    # Owner and manager are defined by exclusion: they hold whatever is in the
    # permission registry, minus what is reserved above them. Deriving the two
    # keeps them from silently falling behind every time a permission is added.
    GENERAL_MANAGER_EXCLUSIONS = %w[manage_account].freeze

    STAFF_TEMPLATES = [
      { name: "Front Desk", slug: "front_desk", permissions: %w[view_bookings view_financial_status manage_bookings override_booking_rate view_guest_records manage_guest_arrival view_room_readiness manage_room_status post_charges post_folio_charges post_folio_payments manage_requests manage_night_audit manage_concierge perform_housekeeping_tasks dispatch_housekeeping_tasks] },
      { name: "Housekeeper", slug: "housekeeper", permissions: %w[manage_room_status manage_requests perform_housekeeping_tasks] }
    ].freeze

    # The one definition of what an account's starting roles hold. db/seeds.rb
    # reads this too, so the two paths cannot drift apart.
    def self.role_templates
      all_slugs = Permission.order(:slug).pluck(:slug)

      [
        { name: "Hotel Owner", slug: "hotel_owner", permissions: all_slugs },
        { name: "General Manager", slug: "general_manager", permissions: all_slugs - GENERAL_MANAGER_EXCLUSIONS },
        *STAFF_TEMPLATES
      ]
    end

    def self.call(account)
      role_templates.each do |t|
        role = Role.find_or_create_by!(account: account, slug: t[:slug]) do |r|
          r.name = t[:name]
        end

        t[:permissions].each do |p_slug|
          permission = Permission.find_by(slug: p_slug)
          RolePermission.find_or_create_by!(role: role, permission: permission) if permission
        end
      end
    end
  end
end
