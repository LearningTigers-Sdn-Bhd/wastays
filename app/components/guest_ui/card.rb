# frozen_string_literal: true

module GuestUI
  # One bounded surface on a guest page.
  #
  # Unlike the portal, where a plain section is the default, a card is the
  # default here. A concierge page is a short stack of unrelated services read
  # on a phone -- housekeeping, then billing, then the front desk -- and with
  # no sidebar and no page chrome around them, a hairline is the only thing
  # that says where one ends.
  #
  # The title is an eyebrow rather than a heading face. These name a group of
  # controls, and a display heading on each would compete with the page's own.
  class Card < GuestUI::BaseComponent
    PADDINGS = %i[default tight].freeze
    VARIANTS = %i[default dashed].freeze

    # A secondary service: a row, not a tile, so the tiles above it stay the
    # primary actions. A row that changes something is a form, like Button.
    class Row < GuestUI::BaseComponent
      def initialize(label:, href:, hint: nil, icon: nil, method: nil, confirm: nil, class: nil, **attributes)
        @label = label
        @href = href
        @hint = hint
        @icon = icon
        @method = method&.to_sym
        @confirm = confirm
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        return helpers.button_to(@href, **form_attributes) { body } if form?

        link_to(@href, **row_attributes) { body }
      end

      private

      def form? = @method.present? && @method != :get

      def body
        safe_join([ icon_tag, text, chevron ].compact)
      end

      def text
        tag.span(class: "guest-card__row-text") do
          safe_join([
            tag.span(@label, class: "guest-card__row-label"),
            (tag.span(@hint, class: "guest-card__row-hint") if @hint.present?)
          ].compact)
        end
      end

      def icon_tag
        return if @icon.blank?

        helpers.app_icon(@icon, class: "guest-card__row-icon", aria: { hidden: "true" })
      end

      # Decorative. The row is already a link, and a screen reader that read
      # this as well would end every service with "right-pointing angle".
      def chevron
        helpers.app_icon("chevron-right", class: "guest-card__row-chevron size-4", aria: { hidden: "true" })
      end

      def row_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        attributes.merge(
          class: tw_merge("guest-card__row group", @class),
          data: data.merge(turbo_confirm: @confirm).compact
        )
      end

      def form_attributes
        row_attributes.merge(method: @method, form: { class: "contents" })
      end
    end

    renders_many :rows, Row

    def initialize(title: nil, padding: :default, variant: :default, class: nil, **attributes)
      @title = title
      @padding = PADDINGS.include?(padding) ? padding : :default
      @variant = VARIANTS.include?(variant) ? variant : :default
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    private

    attr_reader :title

    def card_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("guest-card", @class),
        data: data.merge(padding: @padding, variant: @variant)
      )
    end
  end
end
