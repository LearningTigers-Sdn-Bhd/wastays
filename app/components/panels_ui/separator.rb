# frozen_string_literal: true

module PanelsUI
  class Separator < PanelsUI::BaseComponent
    ORIENTATIONS = %i[horizontal vertical].freeze

    def initialize(orientation: :horizontal, decorative: false, class: nil, **attributes)
      @orientation = ORIENTATIONS.include?(orientation) ? orientation : :horizontal
      @decorative = decorative
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}

      semantic_attributes = if @decorative
        { aria: aria.merge(hidden: "true") }
      else
        { role: attributes.delete(:role) || "separator", aria: aria.merge(orientation: @orientation) }
      end

      tag.div(**attributes.merge(
        class: tw_merge("panel-separator", @class),
        data: data.merge(orientation: @orientation),
        **semantic_attributes
      ))
    end
  end
end
