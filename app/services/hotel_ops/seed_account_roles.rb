module HotelOps
  class SeedAccountRoles
    ROLE_TEMPLATES = [
      { name: "Hotel Owner", slug: "hotel_owner", permissions: %w[manage_account manage_hotel_profile manage_room_types manage_rates manage_inventory view_bookings manage_bookings view_guest_phone manage_guest_arrival view_audit_logs export_audit_logs manage_users manage_room_status post_charges post_folio_charges post_folio_payments execute_folio_refunds post_folio_adjustments post_folio_corrections post_folio_write_offs view_reports view_payouts manage_requests manage_night_audit manage_concierge] },
      { name: "General Manager", slug: "general_manager", permissions: %w[manage_hotel_profile manage_room_types manage_rates manage_inventory view_bookings manage_bookings view_guest_phone manage_guest_arrival view_audit_logs export_audit_logs manage_users manage_room_status post_charges post_folio_charges post_folio_payments execute_folio_refunds post_folio_adjustments post_folio_corrections post_folio_write_offs view_reports view_payouts manage_requests manage_night_audit manage_concierge] },
      { name: "Front Desk", slug: "front_desk", permissions: %w[view_bookings manage_bookings manage_guest_arrival manage_room_status post_charges post_folio_charges post_folio_payments manage_requests manage_night_audit manage_concierge] },
      { name: "Housekeeper", slug: "housekeeper", permissions: %w[manage_room_status manage_requests] }
    ]

    def self.call(account)
      ROLE_TEMPLATES.each do |t|
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
