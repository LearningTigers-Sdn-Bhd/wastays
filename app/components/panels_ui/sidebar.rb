# frozen_string_literal: true

module PanelsUI
  # Data-driven application sidebar. Consumes the Navigation::Section / Navigation::Item
  # trees the portal helpers build (see PanelsUI::Navigation) and renders the desktop
  # aside and a mobile Sheet — a drop-in for the old
  # `shared/navigation/_sidebar_shell` + per-portal `_*_sidebar` partials.
  #
  #   <%= render PanelsUI::Sidebar.new(key: "hotel", home_path: hotel_dashboard_path(hotel),
  #                                    sections: hotel_sidebar_sections,
  #                                    footer_items: hotel_sidebar_footer_items,
  #                                    searchable: true, permanent: true) do |s| %>
  #     <% s.with_header do %> … brand / context … <% end %>
  #   <% end %>
  #
  # Behavior is split across small Stimulus controllers, all namespaced panels-ui--sidebar*:
  #   • panels-ui--sidebar        active-link resync + scroll persistence
  #   • panels-ui--sidebar-toggle desktop hover expansion + navigation-scoped lock
  #   • panels-ui--sidebar-search type-to-filter (only when searchable:)
  #
  # Collapsible, Tooltip, and Popover own their interaction and accessibility contracts;
  # Sidebar only composes them according to the expanded/collapsed presentation.
  class Sidebar < PanelsUI::BaseComponent
    renders_one :header

    def initialize(key:, home_path:, sections: [], footer_items: [],
                   collapsible: true, searchable: false, permanent: false,
                   search_placeholder: "Search navigation",
                   empty_message: "No navigation matches that search.",
                   brand_name: "WAStays", brand_initial: "W", class: nil)
      @key = key
      @home_path = home_path
      @sections = Array(sections)
      @footer_items = Array(footer_items)
      @collapsible = collapsible
      @searchable = searchable
      @permanent = permanent
      @search_placeholder = search_placeholder
      @empty_message = empty_message
      @brand_name = brand_name
      @brand_initial = brand_initial
      @class = binding.local_variable_get(:class)
    end

    attr_reader :key, :home_path, :sections, :footer_items,
                :search_placeholder, :empty_message, :brand_name, :brand_initial

    def searchable? = @searchable
    def collapsible? = @collapsible
    def permanent? = @permanent

    def desktop_id = "#{@key}-sidebar"
    def mobile_id = "#{@key}-sidebar-mobile"
    def desktop_search_id = "#{@key}-sidebar-search-desktop"
    def mobile_search_id = "#{@key}-sidebar-search-mobile"

    # Cookie written by panels-ui--sidebar (client) so the server can render each
    # group's persisted open/closed state on first paint — no post-hydration flash.
    GROUP_STATE_COOKIE = "sidebar_groups"

    def navigation_item_id(surface:, section_index:, item_index:)
      "#{@key}-sidebar-#{surface}-section-#{section_index}-item-#{item_index}"
    end

    # Persisted open state for a collapsible group, falling back to `default`
    # (typically `item.active?`) when the user has never toggled it.
    def group_open?(surface:, section_index:, item_index:, default:)
      id = "#{navigation_item_id(surface: surface, section_index: section_index, item_index: item_index)}-collapsible"
      state = stored_group_states[id]
      state.nil? ? default : state
    end

    def render_sidebar_partial(name, **locals)
      helpers.render(
        partial: "panels_ui/sidebar/#{name}",
        locals: { component: self }.merge(locals)
      )
    end

    # data-controller list for the desktop aside.
    def desktop_controllers
      [ "panels-ui--sidebar", (@searchable ? "panels-ui--sidebar-search" : nil) ].compact.join(" ")
    end

    def mobile_controllers
      [ "panels-ui--sidebar", (@searchable ? "panels-ui--sidebar-search" : nil) ].compact.join(" ")
    end

    private

    # Parse the flat `{ collapsible_id => bool }` map the client persists. Keyed by
    # the fully-qualified collapsible id, so a single cookie covers every portal and
    # surface. Missing/unavailable/malformed cookie ⇒ no stored preferences.
    def stored_group_states
      return @stored_group_states if defined?(@stored_group_states)

      raw = begin
        helpers.request.cookies[GROUP_STATE_COOKIE]
      rescue StandardError
        nil
      end

      @stored_group_states =
        if raw.present?
          parsed = JSON.parse(raw) rescue nil
          parsed.is_a?(Hash) ? parsed : {}
        else
          {}
        end
    end
  end
end
