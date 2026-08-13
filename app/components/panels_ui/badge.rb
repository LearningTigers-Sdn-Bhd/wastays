# frozen_string_literal: true

module PanelsUI
  class Badge < PanelsUI::BaseComponent
    VARIANTS = %i[neutral primary accent info success warning destructive outline].freeze
    SIZES = %i[xs sm md lg].freeze
    SHAPES = %i[rectangular rounded circular].freeze

    def initialize(label: nil, variant: :neutral, size: :md, shape: :rectangular,
                   indicator: false, inverse: false, class: nil, **attributes)
      @label = label
      @variant = VARIANTS.include?(variant) ? variant : :neutral
      @size = SIZES.include?(size) ? size : :md
      @shape = SHAPES.include?(shape) ? shape : :rectangular
      @indicator = indicator
      @inverse = inverse
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      tag.span(
        content.presence || @label,
        **attributes.merge(
          class: tw_merge(badge_class, @class),
          data: data.merge(
            variant: @variant,
            size: @size,
            indicator: (@indicator ? "true" : nil),
            inverse: (@inverse ? "true" : nil)
          ).compact
        )
      )
    end

    private

    def badge_class
      case @shape
      when :circular then "panel-badge-circular"
      when :rounded then "panel-badge-rounded"
      else "panel-badge"
      end
    end
  end
end
