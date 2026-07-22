# frozen_string_literal: true

module CorporatePortal
  module NavigationHelper
    def corporate_sidebar_sections
      return @_corporate_sidebar_sections if defined?(@_corporate_sidebar_sections)

      finance_items = [
        PanelsUI::Navigation::Item.new(
          label: "AR Invoices",
          path: corporate_ar_invoices_path,
          search_text: "AR Invoices Accounts Receivable Direct Bill Outstanding Balance",
          active: controller_name == "ar_invoices",
          icon: "file-text"
        ),
        PanelsUI::Navigation::Item.new(
          label: "Payments",
          path: corporate_ar_payments_path,
          search_text: "Payments Payment History Accounts Receivable",
          active: controller_name == "ar_payments",
          icon: "landmark",
          children: [
            PanelsUI::Navigation::Item.new(label: "Payment History", path: corporate_ar_payments_path, search_text: "Payment History Accounts Receivable Payment Submissions Bank Transfer", active: controller_name.in?(%w[ar_payments ar_payment_submissions]) && !(controller_name == "ar_payments" && action_name.in?(%w[pay_invoices pay_balance choose_method review checkout_session verify])), icon: "history"),
            PanelsUI::Navigation::Item.new(label: "Pay Invoices", path: pay_invoices_corporate_ar_payments_path, search_text: "Pay Invoices Accounts Receivable", active: controller_name == "ar_payments" && action_name.in?(%w[pay_invoices choose_method review checkout_session verify]), icon: "credit-card"),
            PanelsUI::Navigation::Item.new(label: "Pay Account Balance", path: pay_balance_corporate_ar_payments_path, search_text: "Pay Account Balance Lump Sum Accounts Receivable", active: controller_name == "ar_payments" && action_name == "pay_balance", icon: "wallet"),
            PanelsUI::Navigation::Item.new(label: "Submit Payment", path: corporate_ar_payment_submissions_path, search_text: "Submit Payment Slip Bank Transfer Accounts Receivable", active: controller_name == "ar_payment_submissions", icon: "upload")
          ]
        ),
        PanelsUI::Navigation::Item.new(
          label: "Statements",
          path: corporate_ar_statements_path,
          search_text: "Statements Statement of Account Ledger Running Balance Debits Credits",
          active: controller_name == "ar_statements",
          icon: "file-clock"
        )
      ]

      @_corporate_sidebar_sections = [
        PanelsUI::Navigation::Section.new(
          label: "Home",
          items: [
            PanelsUI::Navigation::Item.new(
              label: "Dashboard",
              path: corporate_dashboard_path,
              search_text: "Dashboard Home Linked Hotels Corporate Portal",
              active: controller_name == "dashboard",
              icon: "layout-dashboard"
            )
          ]
        ),
        PanelsUI::Navigation::Section.new(
          label: "Account",
          items: [
            PanelsUI::Navigation::Item.new(
              label: "Profile",
              path: corporate_profile_path,
              search_text: "Profile Corporate Account Company Details Linked Hotels",
              active: controller_name == "profiles",
              icon: "building-2"
            )
          ]
        ),
        PanelsUI::Navigation::Section.new(
          label: "Finance",
          items: finance_items
        )
      ]
    end

    def corporate_sidebar_footer_items
      @_corporate_sidebar_footer_items ||= [
        PanelsUI::Navigation::Item.new(label: "Homepage", path: root_path, search_text: "Homepage Website", icon: "house", active: false)
      ]
    end

    def corporate_breadcrumb_trail
      return @_corporate_breadcrumb_trail if defined?(@_corporate_breadcrumb_trail)

      corporate_sidebar_sections.each do |section|
        section.items.each do |item|
          next unless item.active

          siblings = section.items.map { |sibling| { label: sibling.label, path: sibling.path } }
          return @_corporate_breadcrumb_trail = {
            section: section.label,
            menu: item.label,
            path: item.path,
            siblings: siblings
          }
        end
      end

      @_corporate_breadcrumb_trail = nil
    end

    def corporate_breadcrumb_parts
      return breadcrumb_override if respond_to?(:breadcrumbs_overridden?) && breadcrumbs_overridden?

      appends = respond_to?(:breadcrumb_appends) ? breadcrumb_appends : []
      corporate_default_breadcrumb_parts + appends
    end

    def render_corporate_breadcrumbs
      parts = corporate_breadcrumb_parts
      return if parts.blank?

      render PanelsUI::Breadcrumb.new(id: "corporate-breadcrumb", parts:)
    end

    private

    def corporate_default_breadcrumb_parts
      trail = corporate_breadcrumb_trail
      return [] unless trail

      [
        { type: :section, label: trail[:section] },
        { type: :menu, label: trail[:menu], path: trail[:path], siblings: trail[:siblings] }
      ]
    end
  end
end
