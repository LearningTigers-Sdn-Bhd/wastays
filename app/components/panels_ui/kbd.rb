# frozen_string_literal: true

module PanelsUI
  class Kbd < PanelsUI::BaseComponent
    SIZES = %i[sm md lg].freeze
    VARIANTS = %i[keycap plain].freeze

    def initialize(label: nil, keys: nil, size: :md, variant: :keycap, separator: nil,
                   class: nil, **attributes)
      @label = label
      @keys = Array(keys).compact
      @size = SIZES.include?(size) ? size : :md
      @variant = VARIANTS.include?(variant) ? variant : :keycap
      @separator = separator
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      @keys.any? ? render_combo : render_key(content.presence || @label, @attributes, @class)
    end

    private

    def render_combo
      attributes = @attributes.deep_dup
      aria = attributes.delete(:aria) || {}
      aria[:label] ||= @keys.join("+")

      tag.span(**attributes.merge(
        class: tw_merge("inline-flex items-center gap-1", @class),
        role: attributes.delete(:role) || "group",
        aria: aria
      )) do
        parts = @keys.flat_map.with_index do |key, index|
          rendered = [ render_key(key) ]
          rendered << tag.span(@separator, class: "panel-kbd__separator", aria: { hidden: "true" }) if @separator.present? && index < @keys.length - 1
          rendered
        end
        safe_join(parts)
      end
    end

    def render_key(value, attributes = {}, class_override = nil)
      attributes = attributes.deep_dup
      data = attributes.delete(:data) || {}

      tag.kbd(value, **attributes.merge(
        class: tw_merge("panel-kbd", class_override),
        data: data.merge(size: @size, variant: (@variant == :plain ? :plain : nil)).compact
      ))
    end
  end
end
