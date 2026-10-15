# frozen_string_literal: true

module Guest::NavigationHelper
  def guest_nav_items
    @_guest_nav_items ||= [
      GuestUI::NavItem.new(label: "Home", path: guest_dashboard_path, icon: "house",
                           active: controller_name == "dashboard"),
      GuestUI::NavItem.new(label: "Bookings", path: guest_bookings_path, icon: "calendar-days",
                           active: controller_name == "bookings"),
      GuestUI::NavItem.new(label: "Refunds", path: guest_refund_requests_path, icon: "receipt",
                           active: controller_name == "refund_requests")
    ]
  end

  # The trail from the active destination down to this page: the destination
  # itself, then what the controller appended with `append_breadcrumb`. The
  # portal no longer draws it as a breadcrumb. The Navbar takes its last step
  # as the page title and the step before it as the way back.
  def guest_breadcrumb_parts
    return breadcrumb_override if respond_to?(:breadcrumbs_overridden?) && breadcrumbs_overridden?

    active = guest_nav_items.find(&:active)
    appends = respond_to?(:breadcrumb_appends) ? breadcrumb_appends : []
    [ (active && { label: active.label, path: active.path }), *appends ].compact
  end

  def guest_page_title
    guest_breadcrumb_parts.last&.dig(:label)
  end

  def guest_back_path
    guest_breadcrumb_parts[0...-1].reverse.find { |part| part[:path].present? }&.dig(:path)
  end
end
