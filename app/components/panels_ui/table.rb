# frozen_string_literal: true

module PanelsUI
  class Table < PanelsUI::BaseComponent
    renders_one :header
    renders_one :body
    renders_one :footer

    DENSITIES = %i[default compact].freeze
    HEADER_STYLES = %i[default sentence].freeze

    style base: "panel-table w-full",
          defaults: {}

    def initialize(caption:, density: :default, header_style: :default, striped: false, hoverable: false,
                   sticky_header: false, bordered: true, wrapper_class: nil,
                   class: nil, **attributes)
      @caption = caption
      @density = DENSITIES.include?(density) ? density : :default
      @header_style = HEADER_STYLES.include?(header_style) ? header_style : :default
      @striped = striped
      @hoverable = hoverable
      @sticky_header = sticky_header
      @bordered = bordered
      @wrapper_class = wrapper_class
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def before_render
      raise ArgumentError, "Table caption is required" if @caption.blank?
      raise ArgumentError, "Table header slot is required" unless header?
      raise ArgumentError, "Table body slot is required" unless body?
    end

    def wrapper_classes
      tw_merge("panel-table__wrapper", @wrapper_class)
    end

    def table_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: class_for(class_override: @class),
        data: data.merge(
          density: @density,
          header_style: @header_style,
          striped: @striped.to_s,
          hoverable: @hoverable.to_s,
          sticky_header: @sticky_header.to_s,
          bordered: @bordered.to_s
        )
      )
    end
  end
end
