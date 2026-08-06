# frozen_string_literal: true

module PanelsUI
  class Skeleton < PanelsUI::BaseComponent
    VARIANTS = %i[line block square circle table].freeze

    def initialize(variant: :block, rows: 3, columns: 4, label: "Loading", class: nil, **attributes)
      @variant = VARIANTS.include?(variant) ? variant : :block
      @rows = [ rows.to_i, 1 ].max
      @columns = normalize_columns(columns)
      @label = label.presence || "Loading"
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      table? ? render_table : render_placeholder
    end

    private

    def table? = @variant == :table

    def normalize_columns(columns)
      values = columns.is_a?(Array) ? columns : Array.new([ columns.to_i, 1 ].max)
      values.presence || [ nil ]
    end

    def render_placeholder
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      shape = @variant if %i[square circle].include?(@variant)

      tag.div(**attributes.merge(
        class: tw_merge("panel-skeleton", @class),
        aria: merge_aria(attributes.delete(:aria), hidden: "true"),
        data: data.merge(variant: @variant, shape: shape).compact
      ))
    end

    def render_table
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = merge_aria(attributes.delete(:aria), busy: "true", label: @label)

      tag.div(**attributes.merge(
        class: tw_merge("panel-skeleton-table", @class),
        aria: aria,
        data: data.merge(variant: :table)
      )) do
        safe_join([
          tag.span(@label, class: "sr-only"),
          tag.div(table_rows, class: "panel-skeleton-table__rows", aria: { hidden: "true" })
        ])
      end
    end

    def table_rows
      safe_join(Array.new(@rows) do
        tag.div(class: "panel-skeleton-table__row", style: grid_template) do
          safe_join(@columns.map { |width| tag.span(class: tw_merge("panel-skeleton panel-skeleton-table__cell", width)) })
        end
      end)
    end

    def grid_template
      return nil if @columns.any?(&:present?)

      "grid-template-columns: repeat(#{@columns.length}, minmax(0, 1fr));"
    end

    def merge_aria(aria, **values) = (aria || {}).merge(values)
  end
end
