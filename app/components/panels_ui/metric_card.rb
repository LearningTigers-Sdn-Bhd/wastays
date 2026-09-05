# frozen_string_literal: true

module PanelsUI
  class MetricCard < PanelsUI::BaseComponent
    DENSITIES = %i[compact loose].freeze
    DETAIL_VARIANTS = %i[neutral success warning destructive].freeze
    # `tone` colours the value and the icon; `detail_variant` colours the line
    # underneath. They are separate on purpose: a card can report a green trend
    # under a figure that is not itself a status.
    TONES = %i[neutral success warning destructive].freeze

    def initialize(label:, value: nil, detail: nil, detail_variant: :neutral,
                   tone: :neutral, icon: nil, href: nil, density: :compact,
                   loading: false, class: nil, **attributes)
      raise ArgumentError, "Metric cards require a label" if label.blank?
      raise ArgumentError, "Metric cards require a value unless loading" if value.blank? && !loading

      @label = label
      @value = value
      @detail = detail
      @detail_variant = DETAIL_VARIANTS.include?(detail_variant) ? detail_variant : :neutral
      @tone = TONES.include?(tone) ? tone : :neutral
      @icon = icon
      @href = href
      @density = DENSITIES.include?(density) ? density : :compact
      @loading = loading
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def root_tag = @href.present? ? :a : :article

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      aria[:busy] = "true" if @loading

      attributes.merge(
        href: @href,
        class: tw_merge("panel-metric-card", @class),
        data: data.merge(
          density: @density,
          tone: @tone,
          loading: @loading.to_s,
          interactive: (@href.present? ? "true" : "false")
        ),
        aria: aria.compact
      ).compact
    end
  end
end
