# frozen_string_literal: true

module Guest::NavigationHelper
  NavSection = Struct.new(:label, :items, keyword_init: true)
  NavItem = Struct.new(:label, :path, :search_text, :icon, :active, keyword_init: true)

  def guest_sidebar_sections
    return @_guest_sidebar_sections if defined?(@_guest_sidebar_sections)

    @_guest_sidebar_sections = [
      NavSection.new(
        label: "My Account",
        items: [
          NavItem.new(
            label: "Dashboard",
            path: guest_dashboard_path,
            search_text: "Dashboard Home Overview",
            active: controller_name == "dashboard",
            icon: "layout-dashboard"
          ),
          NavItem.new(
            label: "My Bookings",
            path: guest_bookings_path,
            search_text: "My Bookings Stays Reservations History",
            active: controller_name == "bookings",
            icon: "calendar-days"
          ),
          NavItem.new(
            label: "Refunds",
            path: guest_refund_requests_path,
            search_text: "Refund Requests Cancellations",
            active: controller_name == "refund_requests",
            icon: "file-text"
          )
        ]
      )
    ]
  end

  def guest_sidebar_footer_items
    @_guest_sidebar_footer_items ||= [
      NavItem.new(label: "Homepage", path: root_path, search_text: "Homepage Website", icon: "house", active: false),
      NavItem.new(label: "Help & support", path: help_center_path, search_text: "Help Support FAQ", icon: "circle-question-mark", active: false)
    ]
  end

  def guest_breadcrumb_trail
    return @_guest_breadcrumb_trail if defined?(@_guest_breadcrumb_trail)

    guest_sidebar_sections.each do |section|
      section.items.each do |item|
        next unless item.active

        siblings = section.items.map { |sibling| { label: sibling.label, path: sibling.path } }
        return @_guest_breadcrumb_trail = {
          section: section.label,
          menu: item.label,
          path: item.path,
          siblings: siblings
        }
      end
    end

    @_guest_breadcrumb_trail = nil
  end

  def guest_breadcrumb_parts
    return breadcrumb_override if respond_to?(:breadcrumbs_overridden?) && breadcrumbs_overridden?

    appends = respond_to?(:breadcrumb_appends) ? breadcrumb_appends : []
    guest_default_breadcrumb_parts + appends
  end

  def render_guest_breadcrumbs
    parts = guest_breadcrumb_parts
    return if parts.blank?

    render partial: "shared/navigation/breadcrumb_bar", locals: { parts: parts }
  end

  private

  def guest_default_breadcrumb_parts
    trail = guest_breadcrumb_trail
    return [] unless trail

    [
      { type: :section, label: trail[:section] },
      { type: :menu, label: trail[:menu], path: trail[:path], siblings: trail[:siblings] }
    ]
  end
end
