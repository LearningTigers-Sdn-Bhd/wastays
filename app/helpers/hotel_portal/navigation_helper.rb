# frozen_string_literal: true

module HotelPortal
  module NavigationHelper
    NavSection = Struct.new(:label, :items, keyword_init: true)
    NavItem = Struct.new(:label, :path, :search_text, :icon, :active, :external, :children, :permission, :permission_scope, :plan_feature, keyword_init: true)

    def hotel_sidebar_sections
      return @_hotel_sidebar_sections if defined?(@_hotel_sidebar_sections)

      financial_nav_items = [
        NavItem.new(label: "Summary", path: hotel_reports_path(current_hotel), icon: "file-spreadsheet", active: controller_name == "reports" && action_name == "index"),
        NavItem.new(label: "Manager's Flash Report", path: managers_flash_hotel_reports_path(current_hotel), icon: "trending-up", active: controller_name == "reports" && action_name == "managers_flash", plan_feature: "housekeeper_productivity"),
        NavItem.new(label: "Daily Revenue", path: daily_revenue_hotel_reports_path(current_hotel), icon: "coins", active: controller_name == "reports" && action_name == "daily_revenue", plan_feature: "revenue_allocation_per_night"),
        NavItem.new(label: "Refund Report", path: refund_report_hotel_reports_path(current_hotel), icon: "credit-card", active: controller_name == "reports" && action_name == "refund_report"),
        NavItem.new(label: "Extra Charge", path: extra_charge_hotel_reports_path(current_hotel), icon: "receipt", active: controller_name == "reports" && action_name == "extra_charge"),
        NavItem.new(label: "Daily Occupancy", path: daily_occupancy_hotel_reports_path(current_hotel), icon: "percent", active: controller_name == "reports" && action_name == "daily_occupancy", plan_feature: "daily_occupancy_revenue"),
        NavItem.new(label: "Outstanding Balance", path: outstanding_balance_hotel_reports_path(current_hotel), icon: "wallet", active: controller_name == "reports" && action_name == "outstanding_balance", plan_feature: "outstanding_balance_noshow"),
        NavItem.new(label: "Deposit Liability", path: deposit_liability_hotel_reports_path(current_hotel), icon: "landmark", active: controller_name == "reports" && action_name == "deposit_liability")
      ]
      financial_nav_active = financial_nav_items.any?(&:active)

      guest_compliance_nav_items = [
        NavItem.new(label: "Tourism Tax", path: tourism_tax_hotel_reports_path(current_hotel), icon: "calculator", active: controller_name == "reports" && action_name == "tourism_tax"),
        NavItem.new(label: "SST", path: sst_hotel_reports_path(current_hotel), icon: "calculator", active: controller_name == "reports" && action_name == "sst"),
        NavItem.new(label: "Non-National", path: non_national_hotel_reports_path(current_hotel), icon: "map-pin", active: controller_name == "reports" && action_name == "non_national"),
        NavItem.new(label: "Guest Reports", path: guest_reports_hotel_reports_path(current_hotel), icon: "users", active: controller_name == "reports" && action_name == "guest_reports", plan_feature: "arrivals_departures_list")
      ]
      guest_compliance_nav_active = guest_compliance_nav_items.any?(&:active)

      audit_nav_items = [
        NavItem.new(label: "Night Audit", path: hotel_night_audits_path(current_hotel), icon: "moon", active: controller_name == "night_audits", plan_feature: "no_show_auto_handling")
      ]
      audit_nav_active = audit_nav_items.any?(&:active)

      accounting_nav_items = [
        NavItem.new(label: "Journal Batches", path: journal_batches_hotel_reports_path(current_hotel), icon: "book-open", active: controller_name == "reports" && action_name == "journal_batches", permission: "view_reports"),
        NavItem.new(label: "General Ledger Mappings", path: hotel_general_ledger_maps_path(current_hotel), icon: "git-merge", active: controller_name == "general_ledger_maps", permission: "manage_general_ledger_maps")
      ]
      accounting_nav_active = accounting_nav_items.any?(&:active)

      knowledge_nav_items = [
        NavItem.new(label: "Policy Management", path: hotel_knowledge_policies_path(current_hotel), icon: "file-text", active: controller_name == "knowledge_policies", plan_feature: "ai_concierge_page"),
        NavItem.new(label: "FAQs Management", path: hotel_knowledge_faqs_path(current_hotel), icon: "circle-question-mark", active: controller_name == "knowledge_faqs", plan_feature: "ai_concierge_page"),
        NavItem.new(label: "General Info", path: hotel_knowledge_general_infos_path(current_hotel), icon: "info", active: controller_name == "knowledge_general_infos", plan_feature: "ai_concierge_page"),
        NavItem.new(label: "Knowledge Diagnostics", path: hotel_knowledge_diagnostics_path(current_hotel), icon: "activity", active: controller_name == "knowledge_diagnostics", plan_feature: "ai_concierge_page")
      ]
      knowledge_nav_active = knowledge_nav_items.any?(&:active)

      accounts_receivable_nav_items = [
        NavItem.new(label: "Corporate Accounts", path: hotel_corporate_accounts_path(current_hotel), search_text: "Corporate Accounts Government Direct Bill Credit Terms External Payers Accounts Receivable", active: controller_name.in?(%w[corporate_accounts corporate_invitations]), icon: "building-2", permission: "manage_corporate_accounts"),
        NavItem.new(label: "AR Invoices", path: hotel_ar_invoices_path(current_hotel), search_text: "AR Invoices Accounts Receivable Direct Bill Aging Finance", active: controller_name == "ar_invoices" && action_name != "aging", icon: "file-text", permission: "view_reports"),
        NavItem.new(label: "AR Payments", path: hotel_ar_payments_path(current_hotel), search_text: "AR Payments Corporate Payments Accounts Receivable Finance", active: controller_name == "ar_payments", icon: "landmark", permission: "view_reports"),
        NavItem.new(label: "AR Statements", path: hotel_ar_statements_path(current_hotel), search_text: "AR Statements Corporate Account Statement Ledger Accounts Receivable Finance", active: controller_name == "ar_statements", icon: "file-spreadsheet", permission: "view_reports"),
        NavItem.new(label: "Aging Report", path: hotel_ar_aging_path(current_hotel), search_text: "AR Aging Aging Report Credit Exposure Accounts Receivable Finance", active: controller_name == "ar_invoices" && action_name == "aging", icon: "chart-bar", permission: "view_reports")
      ]
      accounts_receivable_nav_active = accounts_receivable_nav_items.any?(&:active)

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
            NavItem.new(label: "Booking Timeline Board", path: board_hotel_bookings_path(current_hotel), search_text: "Booking Timeline Board Calendar Tape Chart Operations", active: controller_path == "hotel_portal/bookings/board", icon: "table-2", permission: [ "view_reservation_board", "manage_bookings" ]),
            NavItem.new(label: "Room Status", path: hotel_room_status_board_path(current_hotel), search_text: "Room Status Tape Chart Housekeeping Assignment Operations", active: controller_name == "room_status_board", icon: "layout-grid", permission: [ "view_room_readiness", "manage_room_status" ], plan_feature: "room_status_board"),
            NavItem.new(label: "Requests", path: hotel_requests_path(current_hotel), search_text: "Requests Housekeeping Complaint Operations", active: controller_name == "requests", icon: "clipboard-list", permission: "manage_requests", plan_feature: "task_assignment_minibar_log"),
            NavItem.new(label: "Guest Records", path: hotel_guests_path(current_hotel), search_text: "Guest Records Guests Directory", active: controller_name == "guests", icon: "user", permission: "view_guest_records", plan_feature: "unified_guest_profile")
          ]
        ),
        NavSection.new(
          label: "Property",
          items: [
            NavItem.new(label: "Room Categories", path: hotel_room_types_path(current_hotel), search_text: "Room Categories Rooms Property", active: controller_name == "room_types", icon: "layers", permission: "manage_hotel_profile"),
            NavItem.new(label: "Rates & Inventory", path: hotel_inventory_index_path(current_hotel), search_text: "Rates Inventory Calendar Property", active: controller_name == "inventory_dashboards", icon: "calendar-range", permission: "manage_hotel_profile"),
            NavItem.new(label: "Hotel Details", path: edit_hotel_profile_path(current_hotel), search_text: "Hotel Details Profile Property", active: controller_name == "profiles", icon: "building-2", permission: "manage_hotel_profile"),
            NavItem.new(label: "Nearby Attractions", path: hotel_nearby_attractions_path(current_hotel), search_text: "Nearby Attractions Places Around Property", active: controller_name == "nearby_attractions", icon: "map-pin", permission: "manage_hotel_profile"),
            NavItem.new(label: "Knowledge", path: hotel_knowledge_policies_path(current_hotel), search_text: "Knowledge Policies FAQ General Info Property", active: knowledge_nav_active, icon: "file-text", children: knowledge_nav_items, permission: "manage_hotel_profile", plan_feature: "ai_concierge_page")
          ]
        ),
        NavSection.new(
          label: "Finance",
          items: [
            NavItem.new(label: "Folios", path: hotel_folios_path(current_hotel), search_text: "Folios Ledger Guest Balances Refund Due Finance", active: controller_name == "folios" && action_name == "index", icon: "book-open", permission: "view_bookings"),
            NavItem.new(label: "Accounts Receivable", path: hotel_ar_invoices_path(current_hotel), search_text: "Accounts Receivable Corporate Accounts AR Invoices AR Payments Direct Bill Finance", active: accounts_receivable_nav_active, icon: "file-text", children: accounts_receivable_nav_items, permission: [ "view_reports", "manage_corporate_accounts" ]),
            NavItem.new(label: "Taxes & Fees", path: hotel_taxes_fees_path(current_hotel), search_text: "Taxes Fees Property Finance", active: controller_name == "taxes_fees", icon: "receipt", permission: "manage_hotel_profile"),
            NavItem.new(label: "Transaction Codes", path: hotel_transaction_codes_path(current_hotel), search_text: "Transaction Codes Posting Finance", active: controller_name == "transaction_codes", icon: "badge-percent", permission: "manage_hotel_profile"),
            NavItem.new(label: "Payouts", path: payouts_hotel_reports_path(current_hotel), search_text: "Payouts Settlements Finance", active: controller_name == "reports" && action_name == "payouts", icon: "credit-card", permission: "view_payouts")
          ]
        ),
        NavSection.new(
          label: "Team Management",
          items: [
            NavItem.new(label: "Staff Management", path: hotel_users_path(current_hotel), search_text: "Staff Management Users Roles Access Team", active: controller_name == "users", icon: "users", permission: "manage_users"),
            NavItem.new(label: "Roles & Permissions", path: hotel_roles_path(current_hotel), search_text: "Roles Permissions Access Control Team", active: controller_name == "roles", icon: "shield-check", permission: "manage_users", plan_feature: "role_based_access_control")
          ]
        ),
        NavSection.new(
          label: "Reports",
          items: [
            NavItem.new(label: "Financial", path: hotel_reports_path(current_hotel), search_text: "Reports Financial Summary Manager Flash Daily Revenue Refund Extra Charge Daily Occupancy Outstanding Balance Deposit Liability", active: financial_nav_active, icon: "chart-bar", children: financial_nav_items, permission: "view_reports"),
            NavItem.new(label: "Tax & Compliance", path: tourism_tax_hotel_reports_path(current_hotel), search_text: "Reports Tax Compliance Tourism Tax SST Non National Guest Reports", active: guest_compliance_nav_active, icon: "calculator", children: guest_compliance_nav_items, permission: "view_reports"),
            NavItem.new(label: "Audit", path: hotel_night_audits_path(current_hotel), search_text: "Audit Night Audit Business Date Close Reports", active: audit_nav_active, icon: "clipboard-check", children: audit_nav_items, permission: "manage_night_audit")
          ]
        ),
        NavSection.new(
          label: "System",
          items: [
            NavItem.new(label: "Accounting", path: journal_batches_hotel_reports_path(current_hotel), search_text: "Accounting Journal Batches General Ledger Mappings System", active: accounting_nav_active, icon: "file-text", children: accounting_nav_items, permission: [ "view_reports", "manage_general_ledger_maps" ]),
            NavItem.new(label: "Operation Logs", path: hotel_audit_logs_path(current_hotel), search_text: "Operation Logs Audit Activity System", active: controller_name == "audit_logs", icon: "file-text", permission: "view_audit_logs", plan_feature: "full_audit_trail"),
            NavItem.new(label: "Notification Logs", path: hotel_notification_logs_path(current_hotel), search_text: "Notification Logs Messaging Activity System", active: controller_name == "notification_logs", icon: "bell", permission: "view_audit_logs"),
            NavItem.new(label: "Settings", path: hotel_settings_path(current_hotel), search_text: "Settings Preferences System", active: controller_name == "settings", icon: "settings", permission: [ "manage_hotel_profile", "manage_account" ]),
            NavItem.new(label: "Your Plan", path: hotel_plan_path(current_hotel), search_text: "Your Plan Subscription Features Upgrade System", active: controller_name == "plans", icon: "layers")
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
      @_hotel_visible_items[items.object_id] ||= items.select do |item|
        hotel_user_has_permission?(item.permission) && feature_enabled_for_nav_item?(item)
      end
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

    def feature_enabled_for_nav_item?(item)
      return true if item.plan_feature.blank?

      feature_enabled_for_hotel?(item.plan_feature)
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
