module Admin::NavigationHelper
  AdminSection = Struct.new(:label, :items, keyword_init: true)
  AdminItem = Struct.new(:label, :path, :search_text, :icon, :active, :external, keyword_init: true)

  def admin_sidebar_sections
    return @_admin_sidebar_sections if defined?(@_admin_sidebar_sections)

    dashboard_active = controller_name == "dashboard" && action_name != "analytics"
    analytics_active = controller_name == "dashboard" && action_name == "analytics"
    hotels_active = controller_name == "hotels"
    bookings_active = controller_name == "bookings"
    onboarding_active = controller_path == "admin/hotels/onboarding" || controller_path == "admin/hotels/onboarding_sessions"
    salespersons_active = controller_name == "salespersons"
    margin_rules_active = controller_name == "margin_rules"
    setup_fee_rules_active = controller_name == "setup_fee_rules"
    exchange_rates_active = controller_name == "exchange_rates"
    reconciliations_active = controller_name == "reconciliations"
    refund_requests_active = controller_name == "refund_requests"
    payouts_active = controller_name == "payout_batches"
    audit_logs_active = controller_name == "audit_logs"
    observation_deck_active = controller_name == "observation_deck"
    refund_policy_active = controller_name == "refund_policies"
    integrations_active = controller_name == "integrations"
    webhooks_active = controller_name == "webhook_endpoints"
    api_keys_active = controller_name == "api_keys" && action_name != "docs"
    api_docs_active = controller_name == "api_keys" && action_name == "docs"

    @_admin_sidebar_sections = [
      AdminSection.new(
        label: "Home",
        items: [
          AdminItem.new(label: "Dashboard", path: admin_dashboard_path, search_text: "Dashboard", active: dashboard_active, icon: "layout-dashboard"),
          AdminItem.new(label: "Analytics", path: admin_analytics_path, search_text: "Analytics Revenue Margin Reports", active: analytics_active, icon: "chart-bar")
        ]
      ),
      AdminSection.new(
        label: "Operations",
        items: [
          AdminItem.new(label: "Hotels", path: admin_hotels_path, search_text: "Hotels Manage Hotels", active: hotels_active && !onboarding_active, icon: "building-2"),
          AdminItem.new(label: "Onboarding", path: onboarding_admin_hotels_path, search_text: "Onboarding Training Setup", active: onboarding_active, icon: "user-plus"),
          AdminItem.new(label: "Bookings", path: admin_bookings_path, search_text: "Bookings Platform Bookings", active: bookings_active, icon: "calendar-days"),
          AdminItem.new(label: "Salespersons", path: admin_salespersons_path, search_text: "Salespersons Hotel Assignment", active: salespersons_active, icon: "users")
        ]
      ),
      AdminSection.new(
        label: "Finance",
        items: [
          AdminItem.new(label: "Payouts", path: admin_payout_batches_path, search_text: "Payouts Settlements Hotel Payments", active: payouts_active, icon: "credit-card"),
          AdminItem.new(label: "Margin Settings", path: admin_margin_rules_path, search_text: "Margin Settings Margin Rules", active: margin_rules_active, icon: "percent"),
          AdminItem.new(label: "Exchange Rates", path: admin_exchange_rates_path, search_text: "Exchange Rates Currency FX Display Prices", active: exchange_rates_active, icon: "arrow-up-down"),
          AdminItem.new(label: "Setup Fee Settings", path: admin_setup_fee_rules_path, search_text: "Setup Fee Settings Hotel Setup Fees", active: setup_fee_rules_active, icon: "dollar-sign"),
          AdminItem.new(label: "Refund Policy", path: admin_refund_policy_path, search_text: "Refund Policy Guest Refunds Finance", active: refund_policy_active, icon: "rotate-ccw"),
          AdminItem.new(label: "Refund Requests", path: admin_refund_requests_path, search_text: "Refund Requests Guest Refunds Finance", active: refund_requests_active, icon: "file-text"),
          AdminItem.new(label: "Payment Issues", path: admin_reconciliation_dashboard_path, search_text: "Payment Issues Reconciliations", active: reconciliations_active, icon: "banknote")
        ]
      ),
      AdminSection.new(
        label: "System",
        items: [
          AdminItem.new(label: "Audit Logs", path: admin_audit_logs_path, search_text: "Audit Logs System Activity", active: audit_logs_active, icon: "file-text"),
          AdminItem.new(label: "Observation Deck", path: admin_observation_deck_index_path, search_text: "Observation Deck Telescope Debug Mission Control", active: observation_deck_active, icon: "eye", external: true)
        ]
      ),
      AdminSection.new(
        label: "Developers",
        items: [
          AdminItem.new(label: "API Access", path: admin_api_keys_path, search_text: "API Access Keys Integrations", active: api_keys_active, icon: "key"),
          AdminItem.new(label: "Webhooks", path: admin_webhook_endpoints_path, search_text: "Integrations Webhook WhatsApp n8n", active: webhooks_active, icon: "link-2"),
          AdminItem.new(label: "Integrations", path: admin_integrations_path, search_text: "Cloudflare R2 Storage Channel Manager", active: integrations_active, icon: "puzzle"),
          AdminItem.new(label: "Developer Guide", path: docs_admin_api_keys_path, search_text: "API Developer Guide Docs", active: api_docs_active, icon: "book-open")
        ]
      )
    ]
  end

  def admin_sidebar_footer_items
    @_admin_sidebar_footer_items ||= [
      AdminItem.new(label: "Homepage", path: root_path, search_text: "Homepage Website", icon: "house", active: false),
      AdminItem.new(label: "Help & support", path: help_center_path, search_text: "Help Support", icon: "circle-question-mark", active: false)
    ]
  end

  def admin_breadcrumb_trail
    return @_admin_breadcrumb_trail if defined?(@_admin_breadcrumb_trail)

    admin_sidebar_sections.each do |section|
      section.items.each do |item|
        next unless item.active
        return @_admin_breadcrumb_trail = { section: section.label, menu: item.label, path: item.path, siblings: section.items }
      end
    end
    @_admin_breadcrumb_trail = nil
  end

  def admin_breadcrumb_parts
    return breadcrumb_override if respond_to?(:breadcrumbs_overridden?) && breadcrumbs_overridden?

    appends = respond_to?(:breadcrumb_appends) ? breadcrumb_appends : []
    admin_default_breadcrumb_parts + appends
  end

  def render_admin_breadcrumbs
    parts = admin_breadcrumb_parts
    return if parts.blank?

    render partial: "shared/navigation/breadcrumb_bar", locals: { parts: parts }
  end

  private

  def admin_default_breadcrumb_parts
    trail = admin_breadcrumb_trail
    return [] unless trail

    parts = []
    parts << { type: :section, label: trail[:section] }
    parts << { type: :menu, label: trail[:menu], path: trail[:path], siblings: trail[:siblings] }

    parts
  end
end
