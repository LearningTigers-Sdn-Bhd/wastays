# frozen_string_literal: true

module GuestUI
  # The one control a guest presses.
  #
  # A link and a button wear the same face, because to a guest they are the
  # same object. Which one it renders comes from what it does: `href` follows
  # something, `method` changes something. Anything that changes something is a
  # form, so it cannot be reached by following a link.
  class Button < GuestUI::BaseComponent
    VARIANTS = %i[primary secondary ghost destructive].freeze
    SIZES = %i[sm md lg].freeze
    ELEMENTS = %i[button a].freeze

    def initialize(label: nil, variant: :primary, size: :md, as: nil, href: nil, method: nil,
                   disabled: false, block: false, icon: nil, icon_only: false, aria_label: nil,
                   confirm: nil, class: nil, **attributes)
      @label = label
      @variant = VARIANTS.include?(variant) ? variant : :primary
      @size = SIZES.include?(size) ? size : :md
      @element = normalize_element(as)
      @href = href
      @method = method&.to_sym
      @disabled = disabled
      @block = block
      @icon = icon
      @icon_only = icon_only
      @aria_label = aria_label
      @confirm = confirm
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      return helpers.button_to(@href, **button_to_attributes) { body } if form?
      return tag.a(body, **html_attributes) if link?

      tag.button(body, **html_attributes)
    end

    private

    def form? = link? && @method.present? && @method != :get
    def link? = tag_name == :a
    def tag_name = @element || (@href.present? ? :a : :button)

    def normalize_element(element)
      element = element.to_sym if element.respond_to?(:to_sym)
      ELEMENTS.include?(element) ? element : nil
    end

    # The icon is decorative every time. An icon-only button says what it does
    # through its accessible name, and a button with a word beside the icon
    # would otherwise read that word twice.
    def body
      text = content.presence || @label
      return safe_join([ icon_tag, text ].compact) if @icon.present?

      text
    end

    def icon_tag
      helpers.app_icon(@icon, class: "size-4 shrink-0", aria: { hidden: "true" })
    end

    def base_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      aria[:label] ||= @aria_label

      if @icon_only && aria[:label].blank? && aria["label"].blank?
        raise ArgumentError, "Icon-only buttons require an aria_label or aria: { label: ... }"
      end

      attributes.merge(
        class: tw_merge("guest-button", @class),
        data: data.merge(
          variant: @variant,
          size: @size,
          block: (@block ? "true" : nil),
          icon_only: (@icon_only ? "true" : nil),
          turbo_confirm: @confirm
        ).compact,
        aria: aria.compact
      )
    end

    # A disabled <a> has no disabled attribute to set, so it loses its href and
    # leaves the tab order. Leaving the href would make a guest on a keyboard
    # or a screen reader the only one who can still press it -- which is why
    # this draws the tag itself rather than going through link_to, whose first
    # argument is the href whatever the attributes say.
    def html_attributes
      attributes = base_attributes
      return attributes.merge(type: attributes.delete(:type) || "button", disabled: @disabled).compact unless link?

      attributes.merge(
        href: (@disabled ? nil : helpers.url_for(@href)),
        tabindex: (@disabled ? "-1" : attributes.delete(:tabindex)),
        aria: attributes[:aria].merge(disabled: (@disabled ? "true" : nil)).compact
      ).compact
    end

    # button_to owns the form, so the wrapper is collapsed out of the layout.
    # A block button inside a shrink-wrapped form would be as wide as its word
    # rather than as wide as the column it sits in.
    def button_to_attributes
      base_attributes.merge(
        method: @method,
        disabled: @disabled,
        form: { class: (@block ? "contents" : nil) }.compact
      )
    end
  end
end
