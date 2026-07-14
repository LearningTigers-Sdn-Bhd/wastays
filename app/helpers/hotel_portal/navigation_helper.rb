# frozen_string_literal: true

module HotelPortal
  module NavigationHelper
    NavSection = PanelsUI::Navigation::Section
    NavItem = PanelsUI::Navigation::Item

    def hotel_sidebar_sections
      return @_hotel_sidebar_sections if defined?(@_hotel_sidebar_sections)

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
        NavItem.new(label: "AR Invoices", path: hotel_ar_invoices_path(current_hotel), search_text: "AR Invoices Accounts Receivable Direct Bill Aging Finance", active: controller_name == "ar_invoices" && action_name.in?(%w[index show]), icon: "file-text", permission: "view_reports"),
        NavItem.new(label: "Payment Record", path: hotel_ar_payments_path(current_hotel), search_text: "Payment Record AR Payments Payment Submissions Agent Slip Verification Corporate Payments Accounts Receivable Finance", active: controller_name.in?(%w[ar_payments ar_payment_submissions]), icon: "landmark", permission: "view_reports"),
        NavItem.new(label: "AR Statements", path: hotel_ar_statements_path(current_hotel), search_text: "AR Statements Corporate Account Statement Ledger Accounts Receivable Finance", active: controller_name == "ar_statements", icon: "file-spreadsheet", permission: "view_reports"),
        NavItem.new(label: "Aging Report", path: hotel_ar_aging_path(current_hotel), search_text: "AR Aging Aging Report Credit Exposure Accounts Receivable Finance", active: controller_name == "ar_invoices" && action_name == "aging", icon: "chart-bar", permission: "view_reports"),
        NavItem.new(label: "Agent Summary", path: hotel_ar_agent_summary_path(current_hotel), search_text: "Agent Summary Statement Travel Agent Airline Accounts Receivable Finance", active: controller_name == "ar_invoices" && action_name == "agent_summary", icon: "briefcase", permission: "view_reports")
      ]
      accounts_receivable_nav_active = accounts_receivable_nav_items.any?(&:active)

      journal_batch_items = [
        NavItem.new(label: "Journal Batches", path: journal_batches_hotel_reports_path(current_hotel), search_text: "Journal Batches Accounting Reports", icon: "book-open", active: controller_name == "reports" && action_name == "journal_batches", permission: "view_reports")
      ]
      journal_batches_active = journal_batch_items.any?(&:active)

      front_desk_children = [
        NavItem.new(label: "Reservations", path: hotel_front_desk_path(current_hotel), search_text: "Reservations Front Desk Arrivals In-House Guests Departures Check-in Check-out", active: controller_name == "front_desk", icon: "calendar-check-2"),
        NavItem.new(label: "Guest Records", path: hotel_guests_path(current_hotel), search_text: "Guest Records Guests Directory Front Desk", active: controller_name == "guests", icon: "user", permission: "view_guest_records", plan_feature: "unified_guest_profile"),
        NavItem.new(label: "Stay View", path: hotel_stay_view_path(current_hotel), search_text: "Stay View Timeline Board Room Status Housekeeping Planning Operations Calendar Tape Chart Front Desk", active: controller_path == "hotel_portal/stay_view/board", icon: "table-2", permission: [ "view_bookings", "manage_bookings", "view_room_readiness", "manage_room_status" ]),
        NavItem.new(label: "Housekeeping Tasks", path: hotel_housekeeping_tasks_path(current_hotel), search_text: "Housekeeping Tasks Cleaning Room Status Front Desk", active: controller_name == "housekeeping_tasks", icon: "clipboard-check", permission: "manage_housekeeping_tasks", plan_feature: "task_assignment_minibar_log"),
        NavItem.new(label: "Requests", path: hotel_requests_path(current_hotel), search_text: "Requests Housekeeping Complaint Reservations", active: controller_name == "requests", icon: "clipboard-list", permission: "manage_requests", plan_feature: "task_assignment_minibar_log"),
        NavItem.new(label: "Night Audit", path: hotel_night_audits_path(current_hotel), search_text: "Night Audit Business Date Close Reports", active: controller_name == "night_audits", icon: "moon", permission: "manage_night_audit", plan_feature: "no_show_auto_handling")
      ]
      front_desk_active = front_desk_children.any?(&:active)

      reservations_children = [
        NavItem.new(label: "Rates & Inventory", path: hotel_inventory_index_path(current_hotel), search_text: "Rates Inventory Availability Pricing Reservations", active: controller_name == "inventory_dashboards", icon: "calendar-range", permission: "manage_hotel_profile")
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
          NavItem.new(label: "Front Office", path: hotel_front_desk_path(current_hotel), search_text: "Front Office Reservations Guest Operations", active: front_desk_active, icon: "monitor", children: front_desk_children),
          NavItem.new(label: "Planning & Inventory", path: hotel_inventory_index_path(current_hotel), search_text: "Planning Inventory Rates Availability", active: reservations_active, icon: "calendar", children: reservations_children)
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
      items = [
        NavItem.new(label: "Help & support", path: help_center_path, search_text: "Help Support", icon: "circle-question-mark", active: false)
      ]
      if current_user.superadmin?
        items << NavItem.new(label: "Go to Admin Portal", path: admin_dashboard_path, icon: "external-link", external: true)
      end
      items
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

    # Produces the fully authorized navigation tree consumed by PanelsUI::Sidebar.
    # Authorization remains in the portal helper; the component only renders the
    # already-filtered value objects it receives.
    def hotel_visible_sidebar_sections(sections = hotel_sidebar_sections)
      sections.filter_map do |section|
        items = hotel_visible_items(section.items).filter_map do |item|
          attributes = item.to_h.symbolize_keys

          if item.children.present?
            children = hotel_visible_items(item.children).map do |child|
              PanelsUI::Navigation::Item.new(**child.to_h.symbolize_keys)
            end
            next if children.empty?

            attributes[:children] = children
          end

          PanelsUI::Navigation::Item.new(**attributes)
        end
        next if items.empty?

        PanelsUI::Navigation::Section.new(label: section.label, items:)
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
      [ hotel_portal_root_breadcrumb_part ] + hotel_default_breadcrumb_parts + appends
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

      render PanelsUI::Breadcrumb.new(id: "hotel-breadcrumb", parts:)
    end

    def hotel_nav_item_active?(item)
      nav_item_active?(item)
    end

    def hotel_portal_root_breadcrumb_part
      {
        type: :menu,
        label: "Hotel Portal",
        path: hotel_dashboard_path(current_hotel)
      }
    end

    private

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
