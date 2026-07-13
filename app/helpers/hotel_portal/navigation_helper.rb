# frozen_string_literal: true

module HotelPortal
  module NavigationHelper
    NavSection = Struct.new(:label, :items, keyword_init: true)
    NavItem = Struct.new(:label, :path, :search_text, :icon, :active, :external, :children, :permission, :permission_scope, :plan_feature, :active_paths, keyword_init: true)

    def hotel_sidebar_sections
      return @_hotel_sidebar_sections if defined?(@_hotel_sidebar_sections)

      return @_hotel_sidebar_sections = hotel_settings_sidebar_sections if settings_sidebar_mode?

      financial_nav_items = [
        NavItem.new(label: "Summary", path: hotel_reports_path(current_hotel), icon: "file-spreadsheet", active: controller_name == "reports" && action_name == "index", permission: "view_reports"),
        NavItem.new(label: "Manager's Flash Report", path: managers_flash_hotel_reports_path(current_hotel), icon: "trending-up", active: controller_name == "reports" && action_name == "managers_flash", permission: "view_reports", plan_feature: "housekeeper_productivity"),
        NavItem.new(label: "Daily Revenue", path: daily_revenue_hotel_reports_path(current_hotel), icon: "coins", active: controller_name == "reports" && action_name == "daily_revenue", permission: "view_reports", plan_feature: "revenue_allocation_per_night"),
        NavItem.new(label: "Refund Report", path: refund_report_hotel_reports_path(current_hotel), icon: "credit-card", active: controller_name == "reports" && action_name == "refund_report", permission: "view_reports"),
        NavItem.new(label: "Extra Charge", path: extra_charge_hotel_reports_path(current_hotel), icon: "receipt", active: controller_name == "reports" && action_name == "extra_charge", permission: "view_reports"),
        NavItem.new(label: "Daily Occupancy", path: daily_occupancy_hotel_reports_path(current_hotel), icon: "percent", active: controller_name == "reports" && action_name == "daily_occupancy", permission: "view_reports", plan_feature: "daily_occupancy_revenue"),
        NavItem.new(label: "Outstanding Balance", path: outstanding_balance_hotel_reports_path(current_hotel), icon: "wallet", active: controller_name == "reports" && action_name == "outstanding_balance", permission: "view_reports", plan_feature: "outstanding_balance_noshow"),
        NavItem.new(label: "Deposit Liability", path: deposit_liability_hotel_reports_path(current_hotel), icon: "landmark", active: controller_name == "reports" && action_name == "deposit_liability", permission: "view_reports")
      ]
      financial_nav_active = financial_nav_items.any?(&:active)

      guest_compliance_nav_items = [
        NavItem.new(label: "Tourism Tax", path: tourism_tax_hotel_reports_path(current_hotel), icon: "calculator", active: controller_name == "reports" && action_name == "tourism_tax", permission: "view_reports"),
        NavItem.new(label: "SST", path: sst_hotel_reports_path(current_hotel), icon: "calculator", active: controller_name == "reports" && action_name == "sst", permission: "view_reports"),
        NavItem.new(label: "Non-National", path: non_national_hotel_reports_path(current_hotel), icon: "map-pin", active: controller_name == "reports" && action_name == "non_national", permission: "view_reports"),
        NavItem.new(label: "Guest Reports", path: guest_reports_hotel_reports_path(current_hotel), icon: "users", active: controller_name == "reports" && action_name == "guest_reports", permission: "view_reports", plan_feature: "arrivals_departures_list")
      ]
      guest_compliance_nav_active = guest_compliance_nav_items.any?(&:active)

      accounts_receivable_nav_items = [
        NavItem.new(label: "Corporate Accounts", path: hotel_corporate_accounts_path(current_hotel), search_text: "Corporate Accounts Government Direct Bill Credit Terms External Payers Accounts Receivable", active: controller_name.in?(%w[corporate_accounts corporate_invitations]), icon: "building-2", permission: "manage_corporate_accounts"),
        NavItem.new(label: "AR Invoices", path: hotel_ar_invoices_path(current_hotel), search_text: "AR Invoices Accounts Receivable Direct Bill Aging Finance", active: controller_name == "ar_invoices" && action_name != "aging", icon: "file-text", permission: "view_reports"),
        NavItem.new(label: "AR Payments", path: hotel_ar_payments_path(current_hotel), search_text: "AR Payments Corporate Payments Accounts Receivable Finance", active: controller_name == "ar_payments", icon: "landmark", permission: "view_reports"),
        NavItem.new(label: "AR Statements", path: hotel_ar_statements_path(current_hotel), search_text: "AR Statements Corporate Account Statement Ledger Accounts Receivable Finance", active: controller_name == "ar_statements", icon: "file-spreadsheet", permission: "view_reports"),
        NavItem.new(label: "Aging Report", path: hotel_ar_aging_path(current_hotel), search_text: "AR Aging Aging Report Credit Exposure Accounts Receivable Finance", active: controller_name == "ar_invoices" && action_name == "aging", icon: "chart-bar", permission: "view_reports")
      ]
      accounts_receivable_nav_active = accounts_receivable_nav_items.any?(&:active)

      journal_batch_items = [
        NavItem.new(label: "Journal Batches", path: journal_batches_hotel_reports_path(current_hotel), search_text: "Journal Batches Accounting Reports", icon: "book-open", active: controller_name == "reports" && action_name == "journal_batches", permission: "view_reports")
      ]
      journal_batches_active = journal_batch_items.any?(&:active)

      front_desk_children = [
        NavItem.new(label: "Arrivals", path: hotel_arrivals_path(current_hotel), search_text: "Arrivals Check-in Front Desk", active: controller_name == "arrivals", icon: "user-plus", permission: "manage_guest_arrival"),
        NavItem.new(label: "In-House Guests", path: hotel_in_house_guests_path(current_hotel), search_text: "In-House Guests Front Desk", active: controller_name == "in_house_guests", icon: "users", permission: "view_bookings"),
        NavItem.new(label: "Departures", path: hotel_checked_out_guests_path(current_hotel), search_text: "Departures Today's Check-Outs Checked Out Front Desk", active: controller_name == "checked_out_guests", icon: "log-out", permission: "view_bookings"),
        NavItem.new(label: "Room Status", path: hotel_room_status_board_path(current_hotel), search_text: "Room Status Housekeeping Front Desk", active: controller_name == "room_status_board", icon: "layout-grid", permission: [ "view_room_readiness", "manage_room_status" ], plan_feature: "room_status_board"),
        NavItem.new(label: "Requests", path: hotel_requests_path(current_hotel), search_text: "Requests Housekeeping Complaint Reservations", active: controller_name == "requests", icon: "clipboard-list", permission: "manage_requests", plan_feature: "task_assignment_minibar_log"),
        NavItem.new(label: "Night Audit", path: hotel_night_audits_path(current_hotel), search_text: "Night Audit Business Date Close Reports", active: controller_name == "night_audits", icon: "moon", permission: "manage_night_audit", plan_feature: "no_show_auto_handling")
      ]
      front_desk_active = front_desk_children.any?(&:active)

      reservations_children = [
        NavItem.new(label: "Timeline Board", path: board_hotel_bookings_path(current_hotel), search_text: "Timeline Board Booking Calendar Tape Chart Reservations", active: controller_path == "hotel_portal/bookings/board", icon: "table-2", permission: [ "view_reservation_board", "manage_bookings" ]),
        NavItem.new(label: "Bookings", path: hotel_bookings_path(current_hotel), search_text: "Bookings Reservations", active: controller_name == "bookings", icon: "calendar-days", permission: "view_bookings"),
        NavItem.new(label: "Rates & Inventory", path: hotel_inventory_index_path(current_hotel), search_text: "Rates Inventory Availability Pricing Reservations", active: controller_name == "inventory_dashboards", icon: "calendar-range", permission: "manage_hotel_profile"),
        NavItem.new(label: "Guest Records", path: hotel_guests_path(current_hotel), search_text: "Guest Records Guests Directory Reservations", active: controller_name == "guests", icon: "user", permission: "view_guest_records", plan_feature: "unified_guest_profile")
      ]
      reservations_active = reservations_children.any?(&:active)

      billing_children = [
        NavItem.new(label: "Folios", path: hotel_folios_path(current_hotel), search_text: "Folios Ledger Guest Balances Billing", active: controller_name == "folios" && action_name == "index", icon: "book-open", permission: "view_bookings"),
        NavItem.new(label: "Payouts", path: payouts_hotel_reports_path(current_hotel), search_text: "Payouts Settlements Billing", active: controller_name == "reports" && action_name == "payouts", icon: "credit-card", permission: "view_payouts")
      ]
      billing_active = billing_children.any?(&:active)

      logs_children = [
        NavItem.new(label: "Operation Logs", path: hotel_audit_logs_path(current_hotel), search_text: "Operation Logs Audit Tracking History Security", icon: "file-text", active: controller_name == "audit_logs", permission: "view_audit_logs", plan_feature: "full_audit_trail"),
        NavItem.new(label: "Notification Logs", path: hotel_notification_logs_path(current_hotel), search_text: "Notification Logs History Sent Alerts Logs", icon: "bell", active: controller_name == "notification_logs", permission: "view_audit_logs")
      ]
      logs_active = logs_children.any?(&:active)

      @_hotel_sidebar_sections = [
        NavSection.new(label: "", items: [
          NavItem.new(label: "Dashboard", path: hotel_dashboard_path(current_hotel), search_text: "Dashboard Home", active: controller_name == "dashboard", icon: "layout-dashboard", permission: "view_bookings"),
          NavItem.new(label: "Front Desk", path: hotel_arrivals_path(current_hotel), search_text: "Front Desk Operations", active: front_desk_active, icon: "monitor", children: front_desk_children),
          NavItem.new(label: "Reservations", path: hotel_bookings_path(current_hotel), search_text: "Reservations Bookings", active: reservations_active, icon: "calendar", children: reservations_children)
        ]),
        NavSection.new(label: "Billing", items: [
          NavItem.new(label: "Folios", path: hotel_folios_path(current_hotel), search_text: "Folios Ledger Guest Balances Billing", active: controller_name == "folios" && action_name == "index", icon: "book-open", permission: "view_bookings"),
          NavItem.new(label: "Accounts Receivable", path: hotel_ar_invoices_path(current_hotel), search_text: "Accounts Receivable Corporate AR Invoices Payments Billing", active: accounts_receivable_nav_active, icon: "file-text", children: accounts_receivable_nav_items, permission: [ "view_reports", "manage_corporate_accounts" ]),
          NavItem.new(label: "Payouts", path: payouts_hotel_reports_path(current_hotel), search_text: "Payouts Settlements Billing", active: controller_name == "reports" && action_name == "payouts", icon: "credit-card", permission: "view_payouts")
        ]),
        NavSection.new(label: "Reports", items: [
          NavItem.new(label: "Financial", path: hotel_reports_path(current_hotel), search_text: "Reports Financial Summary Manager Flash Daily Revenue Refund Extra Charge Daily Occupancy Outstanding Balance Deposit Liability", active: financial_nav_active, icon: "chart-bar", children: financial_nav_items, permission: "view_reports"),
          NavItem.new(label: "Tax & Compliance", path: tourism_tax_hotel_reports_path(current_hotel), search_text: "Reports Tax Compliance Tourism Tax SST Non National Guest Reports", active: guest_compliance_nav_active, icon: "calculator", children: guest_compliance_nav_items, permission: "view_reports"),
          NavItem.new(label: "Accounting", path: journal_batches_hotel_reports_path(current_hotel), search_text: "Reports Accounting Journal Batches", active: journal_batches_active, icon: "book-open", children: journal_batch_items, permission: "view_reports"),
          NavItem.new(label: "Operation Logs", path: hotel_audit_logs_path(current_hotel), search_text: "Operation Logs Audit Tracking History Security", icon: "file-text", active: controller_name == "audit_logs", permission: "view_audit_logs", plan_feature: "full_audit_trail"),
          NavItem.new(label: "Notification Logs", path: hotel_notification_logs_path(current_hotel), search_text: "Notification Logs History Sent Alerts Logs", icon: "bell", active: controller_name == "notification_logs", permission: "view_audit_logs")
        ])
      ]
    end







    def hotel_sidebar_footer_items
      first_item = if settings_sidebar_mode?
                     NavItem.new(label: "Back to previous page", path: hotel_settings_back_path, icon: "arrow-left", active: false)
                   else
                     NavItem.new(label: "Settings", path: hotel_general_settings_path(current_hotel), search_text: "Settings Preferences Configuration", icon: "settings", active: false, permission: [ "manage_hotel_profile", "manage_account" ])
                   end

      [
        first_item,
        NavItem.new(label: "Homepage", path: root_path, search_text: "Homepage Website", icon: "house", active: false),
        NavItem.new(label: "Help & support", path: help_center_path, search_text: "Help Support", icon: "circle-question-mark", active: false)
      ]
    end

    def hotel_sidebar_mode
      settings_sidebar_mode? ? "settings" : "hotel"
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
        feature_enabled_for_nav_item?(item) && (hotel_user_has_permission?(item.permission) || hotel_visible_items(item.children || []).any?)
      end
    end

    def hotel_breadcrumb_trail
      return @_hotel_breadcrumb_trail if defined?(@_hotel_breadcrumb_trail)

      hotel_sidebar_sections.each do |section|
        visible_items = hotel_visible_items(section.items)
        visible_items.each do |item|
          next unless nav_item_active?(item)

          trail = nav_item_breadcrumb_trail(item, [], visible_items)
          return @_hotel_breadcrumb_trail = trail if trail
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

    def hotel_nav_item_active?(item)
      nav_item_active?(item)
    end

    def settings_tabs_for_group(group)
      case group
      when :general
        [
          hotel_permission_granted?("manage_hotel_profile") ? { label: "General Settings", path: hotel_general_settings_path(current_hotel), icon: "settings", active: controller_name == "settings" && settings_active_page == "general" } : nil,
          hotel_permission_granted?("manage_hotel_profile") ? { label: "Rate Settings", path: hotel_rates_settings_path(current_hotel), icon: "badge-dollar-sign", active: controller_name == "settings" && settings_active_page == "rates" } : nil,
          { label: "Plan & Billing", path: hotel_plan_path(current_hotel), icon: "layers", active: controller_name == "plans" }
        ].compact
      when :property
        [
          { label: "Hotel Details", path: edit_hotel_profile_path(current_hotel), icon: "building-2", active: controller_name == "profiles" },
          { label: "Room Categories", path: hotel_room_types_path(current_hotel), icon: "layers", active: controller_name == "room_types" },
          { label: "Nearby Attractions", path: hotel_nearby_attractions_path(current_hotel), icon: "map-pin", active: controller_name == "nearby_attractions" }
        ]
      when :finance
        [
          hotel_permission_granted?("manage_account") ? { label: "Banking Details", path: hotel_banking_details_settings_path(current_hotel), icon: "landmark", active: controller_name == "settings" && settings_active_page == "banking" } : nil,
          hotel_permission_granted?("manage_hotel_profile") ? { label: "Taxes & Fees", path: hotel_taxes_fees_path(current_hotel), icon: "receipt", active: controller_name == "taxes_fees" } : nil,
          hotel_permission_granted?("manage_hotel_profile") ? { label: "Transaction Codes", path: hotel_transaction_codes_path(current_hotel), icon: "badge-percent", active: controller_name == "transaction_codes" } : nil,
          hotel_permission_granted?("manage_general_ledger_maps") ? { label: "General Ledger Mappings", path: hotel_general_ledger_maps_path(current_hotel), icon: "git-merge", active: controller_name == "general_ledger_maps" } : nil
        ].compact
      when :guest_content
        [
          { label: "AI Concierge", path: hotel_ai_concierge_settings_path(current_hotel), icon: "sparkles", active: controller_name == "settings" && settings_active_page == "ai" },
          { label: "Policies", path: hotel_knowledge_policies_path(current_hotel), icon: "file-text", active: controller_name == "knowledge_policies" },
          { label: "FAQs", path: hotel_knowledge_faqs_path(current_hotel), icon: "circle-question-mark", active: controller_name == "knowledge_faqs" },
          { label: "General Info", path: hotel_knowledge_general_infos_path(current_hotel), icon: "info", active: controller_name == "knowledge_general_infos" },
          { label: "Knowledge Diagnostics", path: hotel_knowledge_diagnostics_path(current_hotel), icon: "activity", active: controller_name == "knowledge_diagnostics" },
          { label: "Notifications", path: hotel_notification_settings_path(current_hotel), icon: "bell", active: controller_name == "settings" && settings_active_page == "notifications" }
        ]
      when :team
        [
          { label: "Staff Management", path: hotel_users_path(current_hotel), icon: "users", active: controller_name == "users" },
          { label: "Roles & Permissions", path: hotel_roles_path(current_hotel), icon: "shield-check", active: controller_name == "roles" }
        ]
      else
        []
      end
    end

    def settings_group_active?(group)
      case group
      when :general
        (controller_name == "settings" && settings_active_page.in?(%w[general rates])) || controller_name == "plans"
      when :property
        controller_name.in?(%w[profiles room_types nearby_attractions])
      when :finance
        (controller_name == "settings" && settings_active_page == "banking") ||
          controller_name.in?(%w[transaction_codes general_ledger_maps taxes_fees])
      when :guest_content
        (controller_name == "settings" && settings_active_page.in?(%w[ai notifications])) ||
          controller_name.in?(%w[knowledge_policies knowledge_faqs knowledge_general_infos knowledge_diagnostics])
      when :team
        controller_name.in?(%w[users roles])
      else
        false
      end
    end

    private

    def settings_active_page
      @presenter&.active_page || params[:settings_page].presence || "general"
    end

    def settings_sidebar_mode?
      controller_name.in?(%w[
        settings profiles taxes_fees
        room_types transaction_codes general_ledger_maps
        nearby_attractions knowledge_policies knowledge_faqs knowledge_general_infos knowledge_diagnostics
        users roles plans
      ])
    end

    def hotel_settings_sidebar_sections
      [
        NavSection.new(label: "Settings", items: [
          NavItem.new(label: "General", path: hotel_general_settings_path(current_hotel), icon: "settings", active: settings_group_active?(:general), permission: "manage_hotel_profile"),
          NavItem.new(label: "Property", path: edit_hotel_profile_path(current_hotel), icon: "building-2", active: settings_group_active?(:property), permission: "manage_hotel_profile"),
          NavItem.new(label: "Finance", path: finance_settings_path, icon: "landmark", active: settings_group_active?(:finance), permission: [ "manage_account", "manage_hotel_profile" ]),
          NavItem.new(label: "Guest Content", path: hotel_ai_concierge_settings_path(current_hotel), icon: "message-square", active: settings_group_active?(:guest_content), permission: "manage_hotel_profile"),
          NavItem.new(label: "Team", path: hotel_users_path(current_hotel), icon: "users", active: settings_group_active?(:team), permission: "manage_users")
        ])
      ]
    end

    def hotel_settings_back_path
      referer = request.referer.to_s
      return hotel_dashboard_path(current_hotel) if referer.blank?

      referer_uri = URI.parse(referer)
      current_uri = URI.parse(request.url)
      return hotel_dashboard_path(current_hotel) unless referer_uri.host == current_uri.host

      if referer_settings_path?(referer_uri.path)
        return hotel_dashboard_path(current_hotel)
      end

      referer_uri.request_uri
    rescue URI::InvalidURIError
      hotel_dashboard_path(current_hotel)
    end

    def finance_settings_path
      return hotel_banking_details_settings_path(current_hotel) if hotel_permission_granted?("manage_account")

      hotel_taxes_fees_path(current_hotel)
    end

    def referer_settings_path?(path)
      return false if path.blank?

      settings_keywords = %w[
        settings profiles taxes_fees
        room_types transaction_codes general_ledger_maps
        nearby_attractions knowledge_policies knowledge_faqs knowledge_general_infos knowledge_diagnostics
        users roles plans
      ]

      settings_keywords.any? { |keyword| path.include?("/#{keyword}") }
    end

    def nav_item_active?(item)
      item.active || hotel_visible_items(item.children || []).any? { |child| nav_item_active?(child) }
    end

    def nav_item_breadcrumb_trail(item, ancestors, siblings)
      return nil unless nav_item_active?(item)

      visible_children = hotel_visible_items(item.children || [])
      active_child = visible_children.find { |child| nav_item_active?(child) }

      if active_child
        next_ancestors = ancestors + [ { type: ancestors.empty? ? :section : :menu_group, label: item.label } ]
        return nav_item_breadcrumb_trail(active_child, next_ancestors, visible_children)
      end

      ancestors + [
        {
          type: :menu,
          label: item.label,
          path: item.path,
          siblings: sibling_links(siblings).map { |sibling| { label: sibling.label, path: sibling.path } }
        }
      ]
    end

    def sibling_links(items)
      items.reject { |item| item.children.present? }
    end

    def hotel_default_breadcrumb_parts
      hotel_breadcrumb_trail || []
    end
  end
end
