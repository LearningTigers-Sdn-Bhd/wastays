# frozen_string_literal: true

module CorporatePortal
  module NavigationHelper
    NavSection = Struct.new(:label, :items, keyword_init: true)
    NavItem = Struct.new(:label, :path, :search_text, :icon, :active, :children, keyword_init: true)

    def corporate_sidebar_sections
      return @_corporate_sidebar_sections if defined?(@_corporate_sidebar_sections)

      finance_items = [
        NavItem.new(
          label: "AR Invoices",
          path: corporate_ar_invoices_path,
          search_text: "AR Invoices Accounts Receivable Direct Bill Outstanding Balance",
          active: controller_name == "ar_invoices",
          icon: "file-text"
        ),
        NavItem.new(
          label: "Payments",
          path: corporate_ar_payments_path,
          search_text: "Payments Payment History Accounts Receivable",
          active: controller_name == "ar_payments",
          icon: "landmark",
          children: [
            NavItem.new(label: "Payment History", path: corporate_ar_payments_path, search_text: "Payment History Accounts Receivable", active: controller_name == "ar_payments" && action_name.in?(%w[index show]), icon: "history"),
            NavItem.new(label: "Pay Invoices", path: pay_invoices_corporate_ar_payments_path, search_text: "Pay Invoices Accounts Receivable", active: controller_name == "ar_payments" && action_name.in?(%w[pay_invoices review checkout_session verify]), icon: "credit-card")
          ]
        )
      ]

      @_corporate_sidebar_sections = [
        NavSection.new(
          label: "Home",
          items: [
            NavItem.new(
              label: "Dashboard",
              path: corporate_dashboard_path,
              search_text: "Dashboard Home Linked Hotels Corporate Portal",
              active: controller_name == "dashboard",
              icon: "layout-dashboard"
            )
          ]
        ),
        NavSection.new(
          label: "Account",
          items: [
            NavItem.new(
              label: "Profile",
              path: corporate_profile_path,
              search_text: "Profile Corporate Account Company Details Linked Hotels",
              active: controller_name == "profiles",
              icon: "building-2"
            )
          ]
        ),
        NavSection.new(
          label: "Finance",
          items: finance_items
        )
      ]
    end

    def corporate_sidebar_footer_items
      @_corporate_sidebar_footer_items ||= [
        NavItem.new(label: "Homepage", path: root_path, search_text: "Homepage Website", icon: "house", active: false),
        NavItem.new(label: "Help & support", path: help_center_path, search_text: "Help Support FAQ", icon: "circle-question-mark", active: false)
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

      render partial: "shared/navigation/breadcrumb_bar", locals: { parts: parts }
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
