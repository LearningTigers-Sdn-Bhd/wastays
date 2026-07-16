# frozen_string_literal: true

module PanelsUI
  class Alert < PanelsUI::BaseComponent
    renders_one :custom_icon
    renders_one :description
    renders_one :actions

    alias_method :with_icon, :with_custom_icon

    TONES = %i[default info success warning destructive].freeze
    ACTIONS_LAYOUTS = %i[inline stacked].freeze
    DEFAULT_ICONS = {
      default: "info",
      info: "info",
      success: "circle-check",
      warning: "triangle-alert",
      destructive: "circle-alert"
    }.freeze

    def initialize(tone: :default, title: nil, dismissible: false, show_icon: true,
                   actions_layout: :inline, role: :status, class: nil, **attributes)
      @tone = TONES.include?(tone) ? tone : :default
      @title = title
      @dismissible = dismissible
      @show_icon = show_icon
      @actions_layout = ACTIONS_LAYOUTS.include?(actions_layout) ? actions_layout : :inline
      @role = role
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def default_icon = DEFAULT_ICONS.fetch(@tone)

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("panel-alert", @class),
        role: @role,
        data: data.merge(
          tone: @tone,
          has_title: @title.present? ? "true" : "false",
          has_icon: @show_icon ? "true" : "false",
          actions_layout: @actions_layout,
          controller: (@dismissible ? "panels-ui--dismissible" : nil)
        ).compact
      ).compact
    end
  end
end
