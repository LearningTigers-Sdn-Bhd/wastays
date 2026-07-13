# frozen_string_literal: true

module PanelsUI
  class Progress < PanelsUI::BaseComponent
    VARIANTS = %i[primary success warning destructive info].freeze
    SIZES = %i[sm md lg].freeze

    def initialize(value: nil, max: 100, variant: :primary, size: :md, label: nil,
                   class: nil, **attributes)
      @max = Float(max)
      raise ArgumentError, "max must be greater than zero" unless @max.positive?

      @value = value.nil? ? nil : Float(value).clamp(0, @max)
      @variant = VARIANTS.include?(variant) ? variant : :primary
      @size = SIZES.include?(size) ? size : :md
      @label = label
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    rescue ArgumentError, TypeError => error
      raise error if error.message == "max must be greater than zero"

      raise ArgumentError, "value and max must be numeric"
    end

    def call
      @value.nil? ? render_indeterminate : render_determinate
    end

    private

    def common_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      aria[:label] ||= @label

      attributes.merge(
        class: tw_merge("panel-progress", @class),
        data: data.merge(
          variant: (@variant == :primary ? nil : @variant),
          size: (@size == :md ? nil : @size)
        ).compact,
        aria: aria.compact
      )
    end

    def render_determinate
      tag.progress(display_value, **common_attributes.merge(value: display_value, max: display_max))
    end

    def render_indeterminate
      attributes = common_attributes
      data = attributes.delete(:data) || {}
      tag.div(**attributes.merge(role: "progressbar", data: data.merge(state: "indeterminate"))) do
        tag.div(class: "panel-progress__indicator")
      end
    end

    def display_value = integer_or_float(@value)
    def display_max = integer_or_float(@max)
    def integer_or_float(number) = number.modulo(1).zero? ? number.to_i : number
  end
end
