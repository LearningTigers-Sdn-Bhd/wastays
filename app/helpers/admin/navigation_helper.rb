module Admin::NavigationHelper
  def admin_sidebar_sections
    return @_admin_sidebar_sections if defined?(@_admin_sidebar_sections)

    dashboard_active = controller_name == "dashboard" && action_name != "analytics"
    analytics_active = controller_name == "dashboard" && action_name == "analytics"
    onboarding_active = controller_path == "admin/hotels/onboarding" || controller_path == "admin/hotels/onboarding_sessions"
    hotels_active = controller_name == "hotels" || onboarding_active
    bookings_active = controller_name == "bookings"
    salespersons_active = controller_name == "salespersons"
    margin_rules_active = controller_name == "margin_rules"
    setup_fee_rules_active = controller_name == "setup_fee_rules"
    exchange_rates_active = controller_name == "exchange_rates"
    booking_sources_active = controller_name == "booking_sources"
    attractions_active = controller_name == "attractions"
    reconciliations_active = controller_name == "reconciliations"
    refund_requests_active = controller_name == "refund_requests"
    payouts_active = controller_name == "payout_batches"
    audit_logs_active = controller_name == "audit_logs"
    observation_deck_active = controller_name == "observation_deck"
    refund_policy_active = controller_name == "refund_policies"
    integrations_active = controller_name == "integrations"
    webhooks_active = controller_name == "webhook_endpoints"
    plans_active = controller_name == "plans"
    api_keys_active = controller_name == "api_keys" && action_name != "docs"
    api_docs_active = controller_name == "api_keys" && action_name == "docs"

    @_admin_sidebar_sections = [
      PanelsUI::Navigation::Section.new(
        label: "Home",
        items: [
          PanelsUI::Navigation::Item.new(label: "Dashboard", path: admin_dashboard_path, search_text: "Dashboard", active: dashboard_active, icon: "layout-dashboard"),
          PanelsUI::Navigation::Item.new(label: "Analytics", path: admin_analytics_path, search_text: "Analytics Revenue Margin Reports", active: analytics_active, icon: "chart-bar")
        ]
      ),
      PanelsUI::Navigation::Section.new(
        label: "Operations",
        items: [
          PanelsUI::Navigation::Item.new(label: "Hotels", path: admin_hotels_path, search_text: "Hotels Manage Hotels Onboarding Training Setup", active: hotels_active, icon: "building-2"),
          PanelsUI::Navigation::Item.new(label: "Bookings", path: admin_bookings_path, search_text: "Bookings Platform Bookings", active: bookings_active, icon: "calendar-days"),
          PanelsUI::Navigation::Item.new(label: "Salespersons", path: admin_salespersons_path, search_text: "Salespersons Hotel Assignment", active: salespersons_active, icon: "users")
        ]
      ),
      PanelsUI::Navigation::Section.new(
        label: "Finance",
        items: [
          PanelsUI::Navigation::Item.new(label: "Payouts", path: admin_payout_batches_path, search_text: "Payouts Settlements Hotel Payments", active: payouts_active, icon: "credit-card"),
          PanelsUI::Navigation::Item.new(label: "Margin Settings", path: admin_margin_rules_path, search_text: "Margin Settings Margin Rules", active: margin_rules_active, icon: "percent"),
          PanelsUI::Navigation::Item.new(label: "Exchange Rates", path: admin_exchange_rates_path, search_text: "Exchange Rates Currency FX Display Prices", active: exchange_rates_active, icon: "arrow-up-down"),
          PanelsUI::Navigation::Item.new(label: "Setup Fee Settings", path: admin_setup_fee_rules_path, search_text: "Setup Fee Settings Hotel Setup Fees", active: setup_fee_rules_active, icon: "dollar-sign"),
          PanelsUI::Navigation::Item.new(label: "Refund Policy", path: admin_refund_policy_path, search_text: "Refund Policy Guest Refunds Finance", active: refund_policy_active, icon: "rotate-ccw"),
          PanelsUI::Navigation::Item.new(label: "Refund Requests", path: admin_refund_requests_path, search_text: "Refund Requests Guest Refunds Finance", active: refund_requests_active, icon: "file-text"),
          PanelsUI::Navigation::Item.new(label: "Payment Issues", path: admin_reconciliation_dashboard_path, search_text: "Payment Issues Reconciliations", active: reconciliations_active, icon: "banknote")
        ]
      ),
      PanelsUI::Navigation::Section.new(
        label: "System",
        items: [
          PanelsUI::Navigation::Item.new(label: "Plan Access", path: admin_plans_path, search_text: "Plan Access Plans Subscription Features Pricing Tiers Gating", active: plans_active, icon: "layers"),
          PanelsUI::Navigation::Item.new(label: "Booking Sources", path: admin_booking_sources_path, search_text: "Booking Sources OTA Logos Walk-in Channel Manager", active: booking_sources_active, icon: "tag"),
          PanelsUI::Navigation::Item.new(label: "Attraction Registry", path: admin_attractions_path, search_text: "Attractions Registry Places Tourism Nearby", active: attractions_active, icon: "map-pin"),
          PanelsUI::Navigation::Item.new(label: "Audit Logs", path: admin_audit_logs_path, search_text: "Audit Logs System Activity", active: audit_logs_active, icon: "file-text"),
          PanelsUI::Navigation::Item.new(label: "Observation Deck", path: admin_observation_deck_index_path, search_text: "Observation Deck Telescope Debug Mission Control", active: observation_deck_active, icon: "eye", external: true)
        ]
      ),
      PanelsUI::Navigation::Section.new(
        label: "Developers",
        items: [
          PanelsUI::Navigation::Item.new(label: "API Access", path: admin_api_keys_path, search_text: "API Access Keys Integrations", active: api_keys_active, icon: "key"),
          PanelsUI::Navigation::Item.new(label: "Webhooks", path: admin_webhook_endpoints_path, search_text: "Integrations Webhook WhatsApp n8n", active: webhooks_active, icon: "link-2"),
          PanelsUI::Navigation::Item.new(label: "Integrations", path: admin_integrations_path, search_text: "Cloudflare R2 Storage Channel Manager", active: integrations_active, icon: "puzzle"),
          PanelsUI::Navigation::Item.new(label: "Developer Guide", path: docs_admin_api_keys_path, search_text: "API Developer Guide Docs", active: api_docs_active, icon: "book-open")
        ]
      )
    ]
  end


  def admin_breadcrumb_trail
    return @_admin_breadcrumb_trail if defined?(@_admin_breadcrumb_trail)

    admin_sidebar_sections.each do |section|
      section.items.each do |item|
        next unless item.active
        siblings = section.items.map { |sibling| { label: sibling.label, path: sibling.path } }
        return @_admin_breadcrumb_trail = { section: section.label, menu: item.label, path: item.path, siblings: }
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

    render PanelsUI::Breadcrumb.new(id: "admin-breadcrumb", parts:)
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
