# frozen_string_literal: true

module PanelsUI
  class Avatar < PanelsUI::BaseComponent
    class Badge < PanelsUI::BaseComponent
      VARIANTS = %i[neutral primary info success warning destructive].freeze

      attr_reader :label

      def initialize(label:, variant: :success, class: nil, **attributes)
        @label = label
        @variant = VARIANTS.include?(variant) ? variant : :success
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "Avatar badge label is required" if @label.blank?
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        tag.span(
          content.presence,
          **attributes.merge(
            class: tw_merge("panel-avatar__badge", @class),
            aria: { hidden: "true" },
            data: data.merge(variant: @variant, slot: "avatar-badge")
          )
        )
      end
    end

    renders_one :badge, ->(**args) { Badge.new(**args) }

    SIZES = %i[sm default lg].freeze

    def initialize(name:, src: nil, size: :default, fallback: nil, icon: nil,
                   class: nil, **attributes)
      @name = name
      @src = src
      @size = SIZES.include?(size) ? size : :default
      @fallback = fallback
      @icon = icon
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def before_render
      raise ArgumentError, "Avatar name is required" if @name.blank?
    end

    def call
      # Ensure a builder-style badge declared in the render block is populated
      # before the root accessible label is composed.
      content

      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      aria[:label] ||= accessible_label

      tag.span(
        **attributes.merge(
          class: tw_merge("panel-avatar", @class),
          role: attributes.delete(:role) || "img",
          aria: aria,
          data: data.merge(
            slot: "avatar",
            size: @size,
            controller: (@src.present? ? "panels-ui--avatar" : nil)
          ).compact
        )
      ) do
        safe_join([ surface, (badge if badge?) ].compact)
      end
    end

    private

    def accessible_label
      [ @name, (badge.label if badge?) ].compact.join(", ")
    end

    def surface
      tag.span(class: "panel-avatar__surface", aria: { hidden: "true" }) do
        safe_join([ fallback_element, image_element ].compact)
      end
    end

    def fallback_element
      tag.span(class: "panel-avatar__fallback", data: { slot: "avatar-fallback" }) do
        if @icon.present?
          helpers.app_icon(@icon, class: "panel-avatar__fallback-icon", aria: { hidden: "true" })
        else
          @fallback.presence || initials
        end
      end
    end

    def image_element
      return if @src.blank?

      tag.img(
        src: @src,
        alt: "",
        class: "panel-avatar__image",
        data: {
          slot: "avatar-image",
          panels_ui__avatar_target: "image",
          action: "error->panels-ui--avatar#hideFailedImage"
        }
      )
    end

    def initials
      tokens = @name.to_s.strip.split(/\s+/)
      selected = tokens.length == 1 ? tokens : [ tokens.first, tokens.last ]
      selected.filter_map { |token| token.scan(/\X/).first }.join.upcase
    end
  end
end
