# frozen_string_literal: true

module HotelPortal
  module NavigationHelper
    NavSection = PanelsUI::Navigation::Section
    NavItem = PanelsUI::Navigation::Item

    def hotel_sidebar_sections
      return @_hotel_sidebar_sections if defined?(@_hotel_sidebar_sections)

      front_desk_children = [
        NavItem.new(label: "Reservations", path: hotel_front_desk_path(current_hotel), search_text: "Reservations Front Desk Arrivals In-House Guests Departures Check-in Check-out", active: controller_name == "front_desk", icon: "calendar-check-2", permission: [ "view_bookings", "manage_guest_arrival" ]),
        NavItem.new(label: "Guest Records", path: hotel_guests_path(current_hotel), search_text: "Guest Records Guests Directory Front Desk", active: controller_name == "guests", icon: "user", permission: "view_guest_records", plan_feature: "unified_guest_profile"),
        NavItem.new(label: "Stay View", path: hotel_stay_view_path(current_hotel), search_text: "Stay View Timeline Board Room Status Housekeeping Planning Operations Calendar Tape Chart Front Desk", active: controller_path == "hotel_portal/stay_view/board", icon: "table-2", permission: [ "view_bookings", "manage_bookings", "view_room_readiness", "manage_room_status" ]),
        NavItem.new(label: "Housekeeping Tasks", path: hotel_housekeeping_tasks_path(current_hotel), search_text: "Housekeeping Tasks Cleaning Room Status Front Desk", active: controller_name == "housekeeping_tasks", icon: "clipboard-check", permission: [ "perform_housekeeping_tasks", "dispatch_housekeeping_tasks" ], plan_feature: "task_assignment_minibar_log"),
        NavItem.new(label: "Requests", path: hotel_requests_path(current_hotel), search_text: "Requests Housekeeping Complaint Reservations", active: controller_name == "requests", icon: "clipboard-list", permission: "manage_requests", plan_feature: "task_assignment_minibar_log"),
        NavItem.new(
          label: "Run Night Audit",
          path: hotel_night_audit_run_path(current_hotel),
          search_text: "Run Night Audit Business Date Close",
          active: false,
          icon: "moon",
          permission: "manage_night_audit",
          plan_feature: "no_show_auto_handling",
          turbo_frame: "booking_action_sheet"
        )
      ]
      front_desk_active = front_desk_children.any?(&:active)

      reservations_children = [
        NavItem.new(label: "Rates & Inventory", path: hotel_inventory_index_path(current_hotel), search_text: "Rates Inventory Availability Pricing Reservations", active: controller_name == "inventory_dashboards", icon: "calendar-range", permission: "manage_hotel_profile")
      ]
      reservations_active = reservations_children.any?(&:active)

      @_hotel_sidebar_sections = [
        NavSection.new(label: "", items: [
          NavItem.new(label: "Dashboard", path: hotel_dashboard_path(current_hotel), search_text: "Dashboard Home", active: controller_name == "dashboard", icon: "layout-dashboard", permission: "view_bookings"),
          NavItem.new(label: "Front Office", search_text: "Front Office Reservations Guest Operations", active: front_desk_active, icon: "monitor", children: front_desk_children),
          NavItem.new(label: "Planning & Inventory", search_text: "Planning Inventory Rates Availability", active: reservations_active, icon: "calendar", children: reservations_children)
        ]),
        NavSection.new(label: "More", items: [
          hotel_layer_nav_item(:financials),
          hotel_layer_nav_item(:reports)
        ])
      ]
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

    # Where a layer's sidebar "home" points. The first entry is not always a
    # link -- a layer can open on a group, whose own path is never rendered --
    # so fall through to its first child rather than handing back nil.
    def hotel_first_nav_path(sections)
      sections.each do |section|
        section.items.each do |item|
          return item.path if item.path.present?

          child = item.children.find { |candidate| candidate.path.present? }
          return child.path if child
        end
      end

      nil
    end

    def hotel_breadcrumb_trail
      return @_hotel_breadcrumb_trail if defined?(@_hotel_breadcrumb_trail)

      @_hotel_breadcrumb_trail = hotel_breadcrumb_trail_for(hotel_sidebar_sections)
    end

    # Walks any layer's navigation tree for the active leaf. Layers differ in
    # what they contain, not in how a trail is built, so each one hands its own
    # sections to this rather than restating the walk.
    def hotel_breadcrumb_trail_for(sections)
      sections.each do |section|
        visible_items = hotel_visible_items(section.items)
        visible_items.each do |item|
          next unless nav_item_active?(item)

          trail = nav_item_breadcrumb_trail(item, [], visible_items)
          return trail if trail
        end
      end

      nil
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

      render PanelsUI::Breadcrumb.new(id: "hotel-breadcrumb", parts:)
    end

    def hotel_nav_item_active?(item)
      nav_item_active?(item)
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
