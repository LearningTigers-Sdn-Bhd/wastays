# frozen_string_literal: true

module PanelsUI
  class Button < PanelsUI::BaseComponent
    VARIANTS = %i[primary secondary accent neutral ghost destructive success warning info].freeze
    SIZES = %i[sm md lg icon_sm icon].freeze

    def initialize(label: nil, variant: :primary, size: :md, href: nil, disabled: false, icon_only: false,
                   aria_label: nil, class: nil, **attributes)
      @label = label
      @variant = VARIANTS.include?(variant) ? variant : :primary
      @size = SIZES.include?(size) ? size : :md
      @href = href
      @disabled = disabled
      @icon_only = icon_only || %i[icon_sm icon].include?(@size)
      @aria_label = aria_label
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      tag.public_send(tag_name, content.presence || @label, **button_attributes)
    end

    private

    def tag_name = @href.present? ? :a : :button

    def button_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      aria[:label] ||= @aria_label

      if @icon_only && aria[:label].blank? && aria["label"].blank?
        raise ArgumentError, "Icon-only buttons require an aria_label or aria: { label: ... }"
      end

      attributes.merge(
        href: (@disabled ? nil : @href),
        type: (@href.present? ? nil : attributes.delete(:type) || "button"),
        disabled: (@href.present? ? nil : @disabled),
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
      @href.present? && @disabled
    end
  end
end
