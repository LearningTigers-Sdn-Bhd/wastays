# frozen_string_literal: true

module PanelsUI
  # Accessible tabs (WAI-ARIA APG "tabs" pattern) — a self-contained widget: the
  # controller root wraps the tablist and the panels, so it is a drop-in for the old
  # hand-rolled `tabs`/`subtabs` markup.
  #
  #   <%= render PanelsUI::Tabs.new(id: "audit", default: "history") do |t| %>
  #     <% t.with_tab(name: "history", label: "Audit History", icon: "history", count: 12) %>
  #     <% t.with_tab(name: "advanced", label: "Advanced Actions") %>
  #     <% t.with_panel(name: "history") do %> … <% end %>
  #     <% t.with_panel(name: "advanced") do %> … <% end %>
  #   <% end %>
  #
  # Keyboard: roving tabindex with ←/→/↑/↓/Home/End (automatic activation). The active
  # tab is synced to the `?tab=` query param (name configurable via `param:`).
  #
  # ── Breadcrumb integration ──────────────────────────────────────────────────────
  # When a PanelsUI::Breadcrumb is on the page, the `panels-ui--tabs` controller reaches
  # it through a Stimulus **outlet** (not a global DOM query) and calls its outlet API on
  # tab change: a `:primary` Tabs sets the tab label + toggles the subtab segment; a
  # `:secondary` (subtab) Tabs sets the subtab label. Absent breadcrumb → no-op.
  class Tabs < PanelsUI::BaseComponent
    LEVELS = %i[primary secondary].freeze
    VARIANTS = %i[pill underline].freeze

    # One tab button (role="tab"). `show_subtab_breadcrumb` (primary level only) reveals
    # the breadcrumb's subtab segment when this tab is active.
    class Tab < PanelsUI::BaseComponent
      def initialize(tabs_id:, name:, label:, icon: nil, count: nil,
                     show_subtab_breadcrumb: false, id: nil, panel_id: nil,
                     href: nil, data: {}, aria: {}, active: false, variant: :pill,
                     navigation: false, class: nil)
        @tabs_id = tabs_id
        @name = name
        @label = label
        @icon = icon
        @count = count
        @show_subtab_breadcrumb = show_subtab_breadcrumb
        @id = id || "#{@tabs_id}-tab-#{@name}"
        @panel_id = panel_id || "#{@tabs_id}-panel-#{@name}"
        @href = href
        @data = data
        @aria = aria
        @active = active
        @variant = variant
        @navigation = navigation
        @class = binding.local_variable_get(:class)
      end

      def call
        return navigation_link if @navigation

        tag.button(
          safe_join([ icon_tag, tag.span(@label), count_tag ].compact),
          type: "button",
          role: "tab",
          id: @id,
          tabindex: (@active ? "0" : "-1"),
          class: tab_classes,
          aria: { selected: (@active ? "true" : "false"), controls: @panel_id }.merge(@aria),
          data: {
            panels_ui__tabs_target: "tab",
            tab_name: @name,
            tab_label: @label,
            show_subtab_breadcrumb: (@show_subtab_breadcrumb ? "true" : nil),
            action: "click->panels-ui--tabs#select"
          }.compact.merge(@data)
        )
      end

      private

      def navigation_link
        helpers.link_to(
          @href,
          id: @id,
          class: tab_classes,
          aria: { current: (@active ? "page" : nil) }.merge(@aria).compact,
          data: {
            panels_ui__tabs_target: "tab",
            tab_name: @name,
            tab_label: @label,
            show_subtab_breadcrumb: (@show_subtab_breadcrumb ? "true" : nil),
            action: "click->panels-ui--tabs#selectNavigation"
          }.compact.merge(@data)
        ) do
          safe_join([ icon_tag, tag.span(@label), count_tag ].compact)
        end
      end

      def tab_classes
        tw_merge("tabs-tab", "tabs-tab--#{@variant}", @class)
      end

      def icon_tag
        return if @icon.blank?

        helpers.app_icon(@icon, class: "size-4 shrink-0", aria: { hidden: "true" })
      end

      def count_tag
        return if @count.nil?

        tag.span(@count, class: "tabs-tab__count")
      end
    end

    # One tab panel (role="tabpanel"). Starts hidden; the controller reveals the active one.
    class Panel < PanelsUI::BaseComponent
      def initialize(tabs_id:, name:, id: nil, tab_id: nil, data: {}, aria: {}, active: false, class: nil)
        @tabs_id = tabs_id
        @name = name
        @id = id || "#{@tabs_id}-panel-#{@name}"
        @tab_id = tab_id || "#{@tabs_id}-tab-#{@name}"
        @data = data
        @aria = aria
        @active = active
        @class = binding.local_variable_get(:class)
      end

      def call
        tag.div(
          content,
          role: "tabpanel",
          id: @id,
          tabindex: "0",
          class: tw_merge("tabs-panel", ("hidden" unless @active), @class),
          aria: { labelledby: @tab_id }.merge(@aria),
          data: { panels_ui__tabs_target: "panel", tab_panel: @name }.merge(@data)
        )
      end
    end

    renders_many :tabs, ->(**args) {
      Tab.new(
        tabs_id: @id,
        active: args[:name].to_s == @default.to_s,
        variant: @variant,
        navigation: @navigation,
        **args
      )
    }
    renders_many :panels, ->(**args) {
      Panel.new(tabs_id: @id, active: args[:name].to_s == @default.to_s, **args)
    }

    def initialize(id: nil, default: nil, param: "tab", level: :primary,
                   sync_url: true, aria_label: nil, breadcrumb_id: nil,
                   variant: :pill, navigation: false, list_class: nil,
                   panels_class: nil, class: nil)
      @id = id || "tabs-#{object_id}"
      @default = default
      @param = param
      @level = LEVELS.include?(level.to_sym) ? level.to_sym : :primary
      @sync_url = ActiveModel::Type::Boolean.new.cast(sync_url) || false
      @aria_label = aria_label
      @breadcrumb_id = breadcrumb_id
      @variant = VARIANTS.include?(variant.to_sym) ? variant.to_sym : :pill
      @navigation = ActiveModel::Type::Boolean.new.cast(navigation) || false
      @list_class = list_class
      @panels_class = panels_class
      @class = binding.local_variable_get(:class)
    end

    attr_reader :param, :level, :aria_label

    def default_value = @default
    def sync_url? = @sync_url
    def navigation? = @navigation
    def variant = @variant

    def breadcrumb_outlet_selector
      "##{@breadcrumb_id}" if @breadcrumb_id.present?
    end
  end
end
