# frozen_string_literal: true

module PanelsUI
  class ButtonGroup < PanelsUI::BaseComponent
    ORIENTATIONS = %i[horizontal vertical].freeze

    class Text < PanelsUI::BaseComponent
      TAGS = %i[div span label].freeze

      def initialize(as: :div, class: nil, **attributes)
        @as = TAGS.include?(as) ? as : :div
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        tag.public_send(
          @as,
          content,
          **attributes.merge(
            class: tw_merge("panel-button-group__text", @class),
            data: data.merge(slot: "button-group-text")
          )
        )
      end
    end

    class Separator < PanelsUI::BaseComponent
      ORIENTATIONS = %i[horizontal vertical].freeze

      def initialize(orientation: :vertical, class: nil, **attributes)
        @orientation = ORIENTATIONS.include?(orientation) ? orientation : :vertical
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}
        aria = attributes.delete(:aria) || {}

        tag.div(
          "",
          **attributes.merge(
            class: tw_merge("panel-button-group__separator", @class),
            data: data.merge(slot: "button-group-separator", orientation: @orientation),
            aria: aria.merge(hidden: "true")
          )
        )
      end
    end

    def initialize(orientation: :horizontal, class: nil, **attributes)
      @orientation = ORIENTATIONS.include?(orientation) ? orientation : :horizontal
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      tag.div(
        content,
        **attributes.merge(
          role: "group",
          class: tw_merge("panel-button-group", @class),
          data: data.merge(slot: "button-group", orientation: @orientation)
        )
      )
    end
  end
end
