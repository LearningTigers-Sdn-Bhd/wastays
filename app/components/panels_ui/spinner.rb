# frozen_string_literal: true

module PanelsUI
  class Spinner < PanelsUI::BaseComponent
    SIZES = %i[sm md lg].freeze
    VARIANTS = %i[default primary success warning destructive info current].freeze
    ORIENTATIONS = %i[horizontal vertical].freeze

    def initialize(label: nil, aria_label: "Loading", size: :md, variant: :default,
                   orientation: :horizontal, class: nil, spinner_class: nil, **attributes)
      @label = label
      @aria_label = aria_label
      @size = SIZES.include?(size) ? size : :md
      @variant = VARIANTS.include?(variant) ? variant : :default
      @orientation = ORIENTATIONS.include?(orientation) ? orientation : :horizontal
      @class = binding.local_variable_get(:class)
      @spinner_class = spinner_class
      @attributes = attributes
    end

    def call
      visible_label? ? render_labeled : render_standalone
    end

    private

    def visible_label? = content.present? || @label.present?

    def render_labeled
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}

      tag.span(**attributes.merge(
        class: tw_merge("panel-loading", @class),
        role: attributes.delete(:role) || "status",
        data: data.merge(orientation: @orientation),
        aria: aria
      )) do
        safe_join([ spinner(aria: { hidden: "true" }), content.presence || @label ])
      end
    end

    def render_standalone
      attributes = @attributes.deep_dup
      aria = attributes.delete(:aria) || {}
      aria[:label] ||= @aria_label

      spinner(
        attributes: attributes,
        class_override: @class,
        role: attributes.delete(:role) || "status",
        aria: aria
      )
    end

    def spinner(attributes: {}, class_override: @spinner_class, **extra_attributes)
      attributes = attributes.deep_dup
      data = attributes.delete(:data) || {}

      tag.span(**attributes.merge(
        class: tw_merge("panel-spinner", class_override),
        data: data.merge(
          size: (@size == :md ? nil : @size),
          variant: (@variant == :default ? nil : @variant)
        ).compact,
        **extra_attributes
      ))
    end
  end
end
