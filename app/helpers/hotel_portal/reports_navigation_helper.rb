# frozen_string_literal: true

module HotelPortal
  # Navigation for the reports layer: everything you read rather than act on.
  # Reports were the single largest block in the operations sidebar and the
  # least urgent -- you go looking for them, they do not come looking for you --
  # which is what makes them a layer rather than a section.
  #
  # Payouts, the daily performance breakdown and the inventory audit log all
  # existed as pages but appeared in no sidebar. They get homes here.
  module ReportsNavigationHelper
    NavSection = PanelsUI::Navigation::Section
    NavItem = PanelsUI::Navigation::Item

    def hotel_reports_sidebar_sections
      return @_hotel_reports_sidebar_sections if defined?(@_hotel_reports_sidebar_sections)

      financial_nav_items = [
        NavItem.new(label: "Summary", path: hotel_reports_path(current_hotel), icon: "file-spreadsheet", active: reports_action?("index"), permission: "view_reports"),
        NavItem.new(label: "Daily Report", path: daily_report_hotel_reports_path(current_hotel), icon: "coins", active: reports_action?("daily_report"), permission: "view_reports", plan_feature: "revenue_allocation_per_night"),
        NavItem.new(label: "Daily Performance Breakdown", path: breakdown_hotel_reports_path(current_hotel), search_text: "Daily Performance Breakdown Detailed Financial Breakdown Reports", icon: "chart-line", active: reports_action?("breakdown"), permission: "view_reports"),
        NavItem.new(label: "Refund Report", path: refund_report_hotel_reports_path(current_hotel), icon: "credit-card", active: reports_action?("refund_report"), permission: "view_reports"),
        NavItem.new(label: "Extra Charge", path: extra_charge_hotel_reports_path(current_hotel), icon: "receipt", active: reports_action?("extra_charge"), permission: "view_reports"),
        NavItem.new(label: "Daily Occupancy", path: daily_occupancy_hotel_reports_path(current_hotel), icon: "percent", active: reports_action?("daily_occupancy"), permission: "view_reports", plan_feature: "daily_occupancy_revenue"),
        NavItem.new(label: "Outstanding Balance", path: outstanding_balance_hotel_reports_path(current_hotel), icon: "wallet", active: reports_action?("outstanding_balance"), permission: "view_reports", plan_feature: "outstanding_balance_noshow"),
        NavItem.new(label: "Deposit Liability", path: deposit_liability_hotel_reports_path(current_hotel), icon: "landmark", active: reports_action?("deposit_liability"), permission: "view_reports"),
        NavItem.new(label: "Payouts", path: payouts_hotel_reports_path(current_hotel), search_text: "Payouts Settlements Weekly Reports", icon: "banknote", active: reports_action?("payouts"), permission: "view_reports")
      ]
      financial_nav_active = financial_nav_items.any?(&:active)

      @_hotel_reports_sidebar_sections = [
        NavSection.new(label: "Reports", items: [
          NavItem.new(label: "Financial", search_text: "Reports Financial Summary Manager Flash Daily Report Revenue Cashier Sales Refund Extra Charge Daily Occupancy Outstanding Balance Deposit Liability Payouts Breakdown", active: financial_nav_active, icon: "chart-bar", children: financial_nav_items, permission: "view_reports"),
          NavItem.new(label: "Tax & Compliance", path: tax_compliance_hotel_reports_path(current_hotel), search_text: "Reports Tax Compliance Tourism Tax SST Non National", active: reports_action?("tax_compliance"), icon: "calculator", permission: "view_reports"),
          NavItem.new(label: "Guest Reports", path: guest_reports_hotel_reports_path(current_hotel), search_text: "Reports Guest Reports Arrivals Departures Checkout Registration Cards", active: reports_action?("guest_reports"), icon: "users", permission: "view_reports", plan_feature: "arrivals_departures_list"),
          NavItem.new(label: "Night Audit History", path: hotel_reports_night_audits_path(current_hotel), search_text: "Reports Night Audit History Business Date Close", active: controller_path == "hotel_portal/reports/night_audits", icon: "moon", permission: [ "view_reports", "manage_night_audit" ], plan_feature: "no_show_auto_handling")
        ]),
        NavSection.new(label: "Logs", items: [
          NavItem.new(label: "Operation Logs", path: hotel_audit_logs_path(current_hotel), search_text: "Operation Logs Audit Tracking History Security", icon: "file-text", active: controller_name == "audit_logs", permission: "view_audit_logs", plan_feature: "full_audit_trail"),
          NavItem.new(label: "Notification Logs", path: hotel_notification_logs_path(current_hotel), search_text: "Notification Logs History Sent Alerts Logs", icon: "bell", active: controller_name == "notification_logs", permission: "view_audit_logs"),
          NavItem.new(label: "Inventory Audit Logs", path: hotel_inventory_audit_logs_path(current_hotel), search_text: "Inventory Audit Logs Rates Changes History", icon: "calendar-range", active: controller_name == "inventory_audit_logs", permission: "view_audit_logs")
        ])
      ]
    end

    def hotel_reports_visible_sidebar_sections
      hotel_visible_sidebar_sections(hotel_reports_sidebar_sections)
    end

    def hotel_reports_landing_path
      hotel_first_nav_path(hotel_reports_visible_sidebar_sections)
    end

    def hotel_reports_breadcrumb_parts
      return breadcrumb_override if respond_to?(:breadcrumbs_overridden?) && breadcrumbs_overridden?

      appends = respond_to?(:breadcrumb_appends) ? breadcrumb_appends : []
      (hotel_breadcrumb_trail_for(hotel_reports_sidebar_sections) || []) + appends
    end

    def render_hotel_reports_breadcrumbs
      parts = hotel_reports_breadcrumb_parts
      return if parts.blank?

      render PanelsUI::Breadcrumb.new(id: "hotel-breadcrumb", parts:)
    end

    private

    # Every financial report is an action on the one reports controller, so the
    # whole section is distinguished by action name alone.
    def reports_action?(action)
      controller_name == "reports" && action_name == action
    end
  end
end
