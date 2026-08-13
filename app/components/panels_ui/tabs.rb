# frozen_string_literal: true

module PanelsUI
  # One compound tab primitive with semantics inferred from its slots:
  # - tabs with hrefs and no panels render link navigation
  # - tabs without hrefs and matching panels render the WAI-ARIA tabs pattern
  class Tabs < PanelsUI::BaseComponent
    VARIANTS = %i[line pill].freeze

    class Tab < PanelsUI::BaseComponent
      attr_reader :name, :id, :panel_id, :href

      def initialize(tabs_id:, name:, label:, icon: nil, count: nil,
                     id: nil, panel_id: nil, href: nil, data: {}, aria: {},
                     active: false, disabled: false, variant: :line, class: nil)
        @tabs_id = tabs_id
        @name = name.to_s
        @label = label
        @icon = icon
        @count = count
        @id = id || "#{@tabs_id}-tab-#{@name}"
        @panel_id = panel_id || "#{@tabs_id}-panel-#{@name}"
        @href = href
        @data = data
        @aria = aria
        @active = active
        @disabled = disabled
        @variant = variant
        @class = binding.local_variable_get(:class)
      end

      def active=(value)
        @active = value
      end

      def label = @label
      def disabled? = @disabled

      def call
        return unavailable if disabled?

        href.present? ? navigation_link : panel_trigger
      end

      private

      # A disabled tab is inert in both modes: not a link, not a tablist stop.
      # It stays in the DOM so the step remains visible and its state announced.
      def unavailable
        tag.span(
          content,
          id: @id,
          class: tab_classes,
          aria: { disabled: "true" }.merge(@aria),
          data: { slot: "tabs-trigger", tab_name: @name, tab_label: @label }.merge(@data)
        )
      end

      def panel_trigger
        tag.button(
          content,
          type: "button",
          role: "tab",
          id: @id,
          tabindex: (@active ? "0" : "-1"),
          class: tab_classes,
          aria: { selected: @active.to_s, controls: @panel_id }.merge(@aria),
          data: {
            slot: "tabs-trigger",
            panels_ui__tabs_target: "tab",
            tab_name: @name,
            tab_label: @label,
            action: "click->panels-ui--tabs#select"
          }.merge(@data)
        )
      end

      def navigation_link
        helpers.link_to(
          @href,
          id: @id,
          class: tab_classes,
          aria: { current: (@active ? "page" : nil) }.merge(@aria).compact,
          data: { slot: "tabs-trigger", tab_name: @name, tab_label: @label }.merge(@data)
        ) { content }
      end

      def content
        safe_join([ icon_tag, tag.span(@label), count_tag ].compact)
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

    class Panel < PanelsUI::BaseComponent
      attr_reader :name, :id, :tab_id

      def initialize(tabs_id:, name:, id: nil, tab_id: nil, data: {}, aria: {}, active: false, class: nil)
        @tabs_id = tabs_id
        @name = name.to_s
        @id = id || "#{@tabs_id}-panel-#{@name}"
        @tab_id = tab_id || "#{@tabs_id}-tab-#{@name}"
        @data = data
        @aria = aria
        @active = active
        @class = binding.local_variable_get(:class)
      end

      def active=(value)
        @active = value
      end

      def call
        tag.div(
          content,
          role: "tabpanel",
          id: @id,
          tabindex: "0",
          hidden: !@active,
          class: tw_merge("tabs-panel", @class),
          aria: { labelledby: @tab_id }.merge(@aria),
          data: { slot: "tabs-panel", panels_ui__tabs_target: "panel", tab_panel: @name }.merge(@data)
        )
      end
    end

    renders_many :tabs, ->(**args) {
      Tab.new(tabs_id: @id, variant: @variant, **args)
    }
    renders_many :panels, ->(**args) {
      Panel.new(tabs_id: @id, **args)
    }

    def initialize(id: nil, active: nil, variant: :line, aria_label: nil, url: nil,
                   list_class: nil, panels_class: nil, class: nil)
      @id = id || "tabs-#{object_id}"
      @active = active&.to_s
      @variant = variant.to_sym
      @aria_label = aria_label
      @url = url
      @list_class = list_class
      @panels_class = panels_class
      @class = binding.local_variable_get(:class)
    end

    def before_render
      validate_and_configure!
    end

    attr_reader :aria_label

    def navigation? = @navigation
    def active_name = @active_name
    def variant = @variant
    def url_param = @url_param

    private

    def validate_and_configure!
      validate_basics!

      # Disabled tabs render inert in either mode, so they carry no href and must
      # not decide (or contradict) the navigation/panel choice.
      href_states = enabled_tabs.map { |tab| tab.href.present? }.uniq
      raise ArgumentError, "PanelsUI::Tabs cannot mix tabs with and without href" if href_states.size > 1
      raise ArgumentError, "PanelsUI::Tabs requires at least one enabled tab" if href_states.empty?

      @navigation = href_states.first
      @navigation ? validate_navigation! : validate_panels!
      configure_active_state!
    end

    def validate_basics!
      raise ArgumentError, "PanelsUI::Tabs requires at least one tab" if tabs.empty?
      raise ArgumentError, "PanelsUI::Tabs requires aria_label" if @aria_label.blank?
      raise ArgumentError, "PanelsUI::Tabs variant must be one of: #{VARIANTS.join(', ')}" unless VARIANTS.include?(@variant)

      validate_unique!(tabs.map(&:name), "tab names")
      validate_unique!(tabs.map(&:id), "tab ids")
      validate_unique!(panels.map(&:name), "panel names")
      validate_unique!(panels.map(&:id), "panel ids")
      configure_url!
    end

    def validate_navigation!
      raise ArgumentError, "PanelsUI::Tabs link navigation cannot contain panels" if panels.any?
      raise ArgumentError, "PanelsUI::Tabs link navigation cannot configure URL state" if @url_param.present?
      return if @active.blank? || tabs.any? { |tab| tab.name == @active }

      raise ArgumentError, "PanelsUI::Tabs active navigation tab #{@active.inspect} does not exist"
    end

    def validate_panels!
      tab_names = tabs.map(&:name)
      panel_names = panels.map(&:name)
      unless tab_names.sort == panel_names.sort
        raise ArgumentError, "PanelsUI::Tabs panel tabs require exactly one matching panel per tab"
      end

      tabs.each do |tab|
        panel = panels.find { |candidate| candidate.name == tab.name }
        next if tab.panel_id == panel.id && panel.tab_id == tab.id

        raise ArgumentError, "PanelsUI::Tabs tab and panel ids must reference each other for #{tab.name.inspect}"
      end
    end

    def configure_active_state!
      @active_name = if navigation?
        @active
      elsif enabled_tabs.any? { |tab| tab.name == @active }
        @active
      else
        enabled_tabs.first.name
      end

      tabs.each { |tab| tab.active = tab.name == @active_name }
      panels.each { |panel| panel.active = panel.name == @active_name }
    end

    def configure_url!
      @url_param = nil
      return if @url.nil?
      unless @url.is_a?(Hash) && @url.keys.map(&:to_sym) == [ :param ] && @url[:param].present?
        raise ArgumentError, "PanelsUI::Tabs url must be nil or { param: \"name\" }"
      end

      @url_param = @url[:param].to_s
    end

    def enabled_tabs = tabs.reject(&:disabled?)

    def validate_unique!(values, label)
      return if values.compact.uniq.size == values.compact.size

      raise ArgumentError, "PanelsUI::Tabs requires unique #{label}"
    end
  end
end
