# frozen_string_literal: true

module PanelsUI
  class Button < PanelsUI::BaseComponent
    VARIANTS = %i[primary secondary accent neutral ghost destructive success warning info].freeze
    SIZES = %i[xs sm md lg icon_xs icon_sm icon icon_lg].freeze
    ELEMENTS = %i[button a].freeze

    def initialize(label: nil, variant: :primary, size: :md, as: nil, href: nil, disabled: false, icon_only: false,
                   aria_label: nil, class: nil, **attributes)
      @label = label
      @variant = VARIANTS.include?(variant) ? variant : :primary
      @size = SIZES.include?(size) ? size : :md
      @element = normalize_element(as)
      @href = href
      @disabled = disabled
      @icon_only = icon_only || %i[icon_xs icon_sm icon icon_lg].include?(@size)
      @aria_label = aria_label
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      tag.public_send(tag_name, content.presence || @label, **button_attributes)
    end

    private

    def tag_name = @element || (@href.present? ? :a : :button)

    def normalize_element(element)
      element = element.to_sym if element.respond_to?(:to_sym)
      ELEMENTS.include?(element) ? element : nil
    end

    def link? = tag_name == :a

    def button_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      aria[:label] ||= @aria_label

      if @icon_only && aria[:label].blank? && aria["label"].blank?
        raise ArgumentError, "Icon-only buttons require an aria_label or aria: { label: ... }"
      end

      attributes.merge(
        href: (link? && !@disabled ? @href : nil),
        type: (link? ? nil : attributes.delete(:type) || "button"),
        disabled: (link? ? nil : @disabled),
        tabindex: disabled_link? ? "-1" : attributes.delete(:tabindex),
        class: tw_merge("panel-button", @class),
        data: data.merge(
          variant: @variant,
          size: @size,
          icon_only: (@icon_only ? "true" : nil)
        ).compact,
        aria: aria.merge(
          disabled: (disabled_link? ? "true" : nil)
        ).compact
      ).compact
    end

    def disabled_link?
      link? && @disabled
    end
  end
end
