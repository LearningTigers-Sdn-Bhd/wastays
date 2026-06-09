module HotelPortal
  module NavigationHelper
    NavSection = Struct.new(:label, :items, keyword_init: true)
    NavItem = Struct.new(:label, :path, :search_text, :icon, :active, :external, :children, :permission, :permission_scope, keyword_init: true)

    def hotel_sidebar_sections
      return @_hotel_sidebar_sections if defined?(@_hotel_sidebar_sections)

      financial_nav_items = [
        NavItem.new(label: "Summary", path: hotel_reports_path(current_hotel), active: controller_name == "reports" && action_name == "index"),
        NavItem.new(label: "Manager's Flash Report", path: managers_flash_hotel_reports_path(current_hotel), active: controller_name == "reports" && action_name == "managers_flash"),
        NavItem.new(label: "Daily Revenue", path: daily_revenue_hotel_reports_path(current_hotel), active: controller_name == "reports" && action_name == "daily_revenue"),
        NavItem.new(label: "Arrivals & Departures", path: arrivals_departures_hotel_reports_path(current_hotel), active: controller_name == "reports" && action_name == "arrivals_departures"),
        NavItem.new(label: "Daily Occupancy", path: daily_occupancy_hotel_reports_path(current_hotel), active: controller_name == "reports" && action_name == "daily_occupancy"),
        NavItem.new(label: "Outstanding Balance", path: outstanding_balance_hotel_reports_path(current_hotel), active: controller_name == "reports" && action_name == "outstanding_balance"),
        NavItem.new(label: "Deposit Liability", path: deposit_liability_hotel_reports_path(current_hotel), active: controller_name == "reports" && action_name == "deposit_liability")
      ]
      financial_nav_active = financial_nav_items.any?(&:active)

      audit_nav_items = [
        NavItem.new(label: "Night Audit", path: hotel_night_audits_path(current_hotel), active: controller_name == "night_audits")
      ]
      audit_nav_active = audit_nav_items.any?(&:active)

      accounting_nav_items = [
        NavItem.new(label: "Journal Batches", path: journal_batches_hotel_reports_path(current_hotel), active: controller_name == "reports" && action_name == "journal_batches", permission: "view_reports"),
        NavItem.new(label: "General Ledger Mappings", path: hotel_general_ledger_maps_path(current_hotel), active: controller_name == "general_ledger_maps", permission: "manage_general_ledger_maps")
      ]
      accounting_nav_active = accounting_nav_items.any?(&:active)

      knowledge_nav_items = [
        NavItem.new(label: "Policy Management", path: hotel_knowledge_policies_path(current_hotel), active: controller_name == "knowledge_policies"),
        NavItem.new(label: "FAQs Management", path: hotel_knowledge_faqs_path(current_hotel), active: controller_name == "knowledge_faqs"),
        NavItem.new(label: "General Info", path: hotel_knowledge_general_infos_path(current_hotel), active: controller_name == "knowledge_general_infos"),
        NavItem.new(label: "Knowledge Diagnostics", path: hotel_knowledge_diagnostics_path(current_hotel), active: controller_name == "knowledge_diagnostics")
      ]
      knowledge_nav_active = knowledge_nav_items.any?(&:active)

      @_hotel_sidebar_sections = [
        NavSection.new(
          label: "Home",
          items: [
            NavItem.new(label: "Dashboard", path: hotel_dashboard_path(current_hotel), search_text: "Dashboard Home", active: controller_name == "dashboard", icon: "layout-dashboard", permission: "view_bookings")
          ]
        ),
        NavSection.new(
          label: "Operations",
          items: [
            NavItem.new(label: "Arrivals", path: hotel_arrivals_path(current_hotel), search_text: "Arrivals Check-in Operations", active: controller_name == "arrivals", icon: "user-plus", permission: "manage_guest_arrival"),
            NavItem.new(label: "In-House Guest", path: hotel_in_house_guests_path(current_hotel), search_text: "In-House Guests Operations", active: controller_name == "in_house_guests", icon: "users", permission: "view_bookings"),
            NavItem.new(label: "Today's Check-Outs", path: hotel_checked_out_guests_path(current_hotel), search_text: "Today's Check-Outs Checked Out Departures Operations", active: controller_name == "checked_out_guests", icon: "log-out", permission: "view_bookings"),
            NavItem.new(label: "Bookings", path: hotel_bookings_path(current_hotel), search_text: "Bookings Reservations Operations", active: controller_name == "bookings", icon: "calendar-days", permission: "view_bookings"),
            NavItem.new(label: "Reservation Board", path: hotel_reservation_board_index_path(current_hotel), search_text: "Reservation Board Timeline Calendar Tape Chart Operations", active: controller_path.start_with?("hotel_portal/reservation_board"), icon: "table-2", permission: [ "view_reservation_board", "manage_bookings" ]),
            NavItem.new(label: "Room Status", path: hotel_room_status_board_path(current_hotel), search_text: "Room Status Tape Chart Housekeeping Assignment Operations", active: controller_name == "room_status_board", icon: "layout-grid", permission: [ "view_room_readiness", "manage_room_status" ]),
            NavItem.new(label: "Requests", path: hotel_requests_path(current_hotel), search_text: "Requests Housekeeping Complaint Operations", active: controller_name == "requests", icon: "clipboard-list", permission: "manage_requests"),
            NavItem.new(label: "Guest Records", path: hotel_guests_path(current_hotel), search_text: "Guest Records Guests Directory", active: controller_name == "guests", icon: "user", permission: "view_bookings")
          ]
        ),
        NavSection.new(
          label: "Property",
          items: [
            NavItem.new(label: "Room Categories", path: hotel_room_types_path(current_hotel), search_text: "Room Categories Rooms Property", active: controller_name == "room_types", icon: "layers", permission: "manage_hotel_profile"),
            NavItem.new(label: "Nearby Attractions", path: hotel_nearby_attractions_path(current_hotel), search_text: "Nearby Attractions Places Around Property", active: controller_name == "nearby_attractions", icon: "map-pin", permission: "manage_hotel_profile"),
            NavItem.new(label: "Rates & Inventory", path: hotel_inventory_index_path(current_hotel), search_text: "Rates Inventory Calendar Property", active: controller_name == "inventory_dashboards", icon: "calendar-range", permission: "manage_hotel_profile"),
            NavItem.new(label: "Hotel Details", path: edit_hotel_profile_path(current_hotel), search_text: "Hotel Details Profile Property", active: controller_name == "profiles", icon: "building-2", permission: "manage_hotel_profile"),
            NavItem.new(label: "Knowledge", path: hotel_knowledge_policies_path(current_hotel), search_text: "Knowledge Policies FAQ General Info Property", active: knowledge_nav_active, icon: "file-text", children: knowledge_nav_items, permission: "manage_hotel_profile")
          ]
        ),
        NavSection.new(
          label: "Team Management",
          items: [
            NavItem.new(label: "Staff Management", path: hotel_users_path(current_hotel), search_text: "Staff Management Users Roles Access Team", active: controller_name == "users", icon: "users", permission: "manage_users"),
            NavItem.new(label: "Roles & Permissions", path: hotel_roles_path(current_hotel), search_text: "Roles Permissions Access Control Team", active: controller_name == "roles", icon: "shield-check", permission: "manage_users")
          ]
        ),
        NavSection.new(
          label: "Reports",
          items: [
            NavItem.new(label: "Financial", path: hotel_reports_path(current_hotel), search_text: "Reports Financial Summary Manager Flash Daily Revenue Arrivals Departures Daily Occupancy Outstanding Balance Deposit Liability", active: financial_nav_active, icon: "chart-bar", children: financial_nav_items, permission: "view_reports"),
            NavItem.new(label: "Audit", path: hotel_night_audits_path(current_hotel), search_text: "Audit Night Audit Business Date Close Reports", active: audit_nav_active, icon: "clipboard-check", children: audit_nav_items, permission: "manage_night_audit")
          ]
        ),
        NavSection.new(
          label: "System",
          items: [
            NavItem.new(label: "Accounting", path: journal_batches_hotel_reports_path(current_hotel), search_text: "Accounting Journal Batches General Ledger Mappings System", active: accounting_nav_active, icon: "file-text", children: accounting_nav_items, permission: [ "view_reports", "manage_general_ledger_maps" ]),
            NavItem.new(label: "Payouts", path: payouts_hotel_reports_path(current_hotel), search_text: "Payouts Settlements System", active: controller_name == "reports" && action_name == "payouts", icon: "credit-card", permission: "view_payouts"),
            NavItem.new(label: "Operation Logs", path: hotel_audit_logs_path(current_hotel), search_text: "Operation Logs Audit Activity System", active: controller_name == "audit_logs", icon: "file-text", permission: "view_audit_logs"),
            NavItem.new(label: "Notification Logs", path: hotel_notification_logs_path(current_hotel), search_text: "Notification Logs Messaging Activity System", active: controller_name == "notification_logs", icon: "bell", permission: "view_audit_logs"),
            NavItem.new(label: "Settings", path: hotel_settings_path(current_hotel), search_text: "Settings Preferences System", active: controller_name == "settings", icon: "settings", permission: [ "manage_hotel_profile", "manage_account" ])
          ]
        )
      ]
    end

    def hotel_sidebar_footer_items
      @_hotel_sidebar_footer_items ||= [
        NavItem.new(label: "Homepage", path: root_path, search_text: "Homepage Website", icon: "house", active: false),
        NavItem.new(label: "Help & support", path: help_center_path, search_text: "Help Support", icon: "circle-question-mark", active: false)
      ]
    end

    def hotel_user_has_permission?(permission)
      return true if permission.blank?
      perms = Array(permission).compact
      return true if perms.blank?

      perms.any? { |p| hotel_permission_granted?(p) }
    end

    def hotel_visible_items(items)
      @_hotel_visible_items ||= {}
      @_hotel_visible_items[items.object_id] ||= items.select { |item| hotel_user_has_permission?(item.permission) }
    end

    def hotel_breadcrumb_trail
      return @_hotel_breadcrumb_trail if defined?(@_hotel_breadcrumb_trail)

      hotel_sidebar_sections.each do |section|
        visible_items = hotel_visible_items(section.items)
        visible_items.each do |item|
          next unless item.active

          if item.children.present?
            visible_children = hotel_visible_items(item.children)
            visible_children.each do |child|
              if child.active
                siblings = visible_children.map { |c| { label: c.label, path: c.path } }
                return @_hotel_breadcrumb_trail = { section: section.label, menu_group: item.label, breakdown: child.label, breakdown_path: child.path, siblings: siblings }
              end
            end
            siblings = visible_children.map { |c| { label: c.label, path: c.path } }
            return @_hotel_breadcrumb_trail = { section: section.label, menu_group: item.label, siblings: siblings }
          else
            siblings = visible_items.reject { |i| i.children.present? }.map { |i| { label: i.label, path: i.path } }
            return @_hotel_breadcrumb_trail = { section: section.label, menu: item.label, menu_path: item.path, siblings: siblings }
          end
        end
      end
      @_hotel_breadcrumb_trail = nil
    end

    def hotel_breadcrumb_parts
      return breadcrumb_override if respond_to?(:breadcrumbs_overridden?) && breadcrumbs_overridden?

      appends = respond_to?(:breadcrumb_appends) ? breadcrumb_appends : []
      hotel_default_breadcrumb_parts + appends
    end

    def hotel_permission_granted?(permission)
      return false unless current_user

      @_hotel_permission_grants ||= {}
      key = [ current_user&.id, current_hotel&.id, permission ]
      return @_hotel_permission_grants[key] if @_hotel_permission_grants.key?(key)

      @_hotel_permission_grants[key] = current_user.has_permission?(permission, hotel: current_hotel) || current_user.has_permission?(permission)
    end

    def render_hotel_breadcrumbs
      parts = hotel_breadcrumb_parts
      return if parts.blank?

      render partial: "shared/navigation/breadcrumb_bar", locals: { parts: parts }
    end

    private

    def hotel_default_breadcrumb_parts
      trail = hotel_breadcrumb_trail
      return [] unless trail

      parts = []
      parts << { type: :section, label: trail[:section] }

      if trail[:menu_group]
        parts << { type: :menu_group, label: trail[:menu_group] }
        parts << { type: :breakdown, label: trail[:breakdown], path: trail[:breakdown_path], siblings: trail[:siblings] }
      elsif trail[:menu]
        parts << { type: :menu, label: trail[:menu], path: trail[:menu_path], siblings: trail[:siblings] }
      end

      parts
    end
  end
end
