# frozen_string_literal: true

module PanelsUI
  class AttachmentGroup < PanelsUI::BaseComponent
    LAYOUTS = %i[list grid].freeze
    SIZES = %i[default lg].freeze

    def initialize(layout: :list, size: :default, class: nil, **attributes)
      @layout = LAYOUTS.include?(layout) ? layout : :list
      @size = SIZES.include?(size) ? size : :default
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      tag.div(content, **attributes.merge(
        class: tw_merge("panel-attachment-group", @class),
        role: attributes.delete(:role) || "list",
        data: data.merge(layout: @layout, size: @size)
      ))
    end
  end
end
