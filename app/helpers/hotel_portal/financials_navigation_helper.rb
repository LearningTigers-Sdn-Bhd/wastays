# frozen_string_literal: true

module HotelPortal
  # Navigation for the financials layer: guest folios and everything owed by an
  # external payer. It moved out of the operations sidebar because it is
  # back-office work on a different rhythm to the front desk -- and because
  # Folios had no sidebar home at all, reachable only from search.
  module FinancialsNavigationHelper
    NavSection = PanelsUI::Navigation::Section
    NavItem = PanelsUI::Navigation::Item

    def hotel_financials_sidebar_sections
      return @_hotel_financials_sidebar_sections if defined?(@_hotel_financials_sidebar_sections)

      cashiering_nav_items = [
        NavItem.new(label: "External Accounts", path: hotel_corporate_accounts_path(current_hotel), search_text: "External Accounts Corporate Accounts Government Direct Bill Credit Terms External Payers Accounts Receivable", active: controller_name.in?(%w[corporate_accounts corporate_invitations]), icon: "building-2", permission: "manage_corporate_accounts"),
        NavItem.new(label: "Invoices", path: hotel_ar_invoices_path(current_hotel), search_text: "Invoices AR Invoices Accounts Receivable Direct Bill Aging Finance", active: controller_name == "ar_invoices" && action_name.in?(%w[index show]), icon: "file-text", permission: "view_reports"),
        NavItem.new(label: "Payment Record", path: hotel_ar_payments_path(current_hotel), search_text: "Payment Record AR Payments Payment Submissions Agent Slip Verification Corporate Payments Accounts Receivable Finance", active: controller_name.in?(%w[ar_payments ar_payment_submissions]), icon: "landmark", permission: "view_reports"),
        NavItem.new(label: "Statements", path: hotel_ar_statements_path(current_hotel), search_text: "Statements AR Statements Corporate Account Statement Ledger Accounts Receivable Finance", active: controller_name == "ar_statements", icon: "file-spreadsheet", permission: "view_reports"),
        NavItem.new(label: "Aging Report", path: hotel_ar_aging_path(current_hotel), search_text: "AR Aging Aging Report Credit Exposure Agent Summary Travel Agent Airline Accounts Receivable Finance", active: controller_name == "ar_invoices" && action_name == "aging", icon: "chart-bar", permission: "view_reports")
      ]
      @_hotel_financials_sidebar_sections = [
        NavSection.new(label: "", items: [
          NavItem.new(label: "Folios", path: hotel_folios_path(current_hotel), search_text: "Folios Guest Folios Ledger Balances Balance Due Refund Due Finance", active: controller_path.start_with?("hotel_portal/folios"), icon: "receipt", permission: "view_bookings")
        ]),
        NavSection.new(label: "Cashiering", items: cashiering_nav_items)
      ]
    end

    def hotel_financials_visible_sidebar_sections
      hotel_visible_sidebar_sections(hotel_financials_sidebar_sections)
    end

    def hotel_financials_landing_path
      hotel_first_nav_path(hotel_financials_visible_sidebar_sections)
    end

    def hotel_financials_breadcrumb_parts
      return breadcrumb_override if respond_to?(:breadcrumbs_overridden?) && breadcrumbs_overridden?

      appends = respond_to?(:breadcrumb_appends) ? breadcrumb_appends : []
      (hotel_breadcrumb_trail_for(hotel_financials_sidebar_sections) || []) + appends
    end

    def render_hotel_financials_breadcrumbs
      parts = hotel_financials_breadcrumb_parts
      return if parts.blank?

      render PanelsUI::Breadcrumb.new(id: "hotel-breadcrumb", parts:)
    end
  end
end
