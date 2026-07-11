# frozen_string_literal: true

module PanelsUI
  class Banner < PanelsUI::BaseComponent
    renders_one :custom_icon
    renders_one :description
    renders_one :actions

    alias_method :with_icon, :with_custom_icon

    TONES = %i[default info success warning destructive].freeze
    APPEARANCES = %i[full floating].freeze
    STRATEGIES = %i[static fixed].freeze
    POSITIONS = %i[top bottom].freeze
    DEFAULT_ICONS = {
      default: "megaphone",
      info: "info",
      success: "circle-check",
      warning: "triangle-alert",
      destructive: "circle-alert"
    }.freeze

    def initialize(tone: :default, title: nil, dismissible: false, show_icon: true,
                   role: :status, appearance: :full, strategy: :static, position: :top,
                   class: nil, **attributes)
      @tone = TONES.include?(tone) ? tone : :default
      @title = title
      @dismissible = dismissible
      @show_icon = show_icon
      @role = role
      @appearance = APPEARANCES.include?(appearance) ? appearance : :full
      @strategy = STRATEGIES.include?(strategy) ? strategy : :static
      @position = POSITIONS.include?(position) ? position : :top
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def default_icon = DEFAULT_ICONS.fetch(@tone)

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("panel-banner", @class),
        role: @role,
        data: data.merge(
          tone: @tone,
          appearance: @appearance,
          strategy: @strategy,
          position: @position,
          controller: (@dismissible ? "panels-ui--dismissible" : nil)
        ).compact
      ).compact
    end
  end
end
