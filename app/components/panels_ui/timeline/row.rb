# frozen_string_literal: true

module PanelsUI
  module Timeline
    class Row < PanelsUI::BaseComponent
      renders_one :summary
      renders_many :cells, ->(**args) { Cell.new(**args) }
      renders_many :segments

      def initialize(track_count:, accessible_label:, class: nil, **attributes)
        @track_count = track_count
        @accessible_label = accessible_label
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "Timeline row accessible_label is required" if @accessible_label.blank?
        raise ArgumentError, "Timeline row summary slot is required" unless summary?
        unless cells.size == @track_count / 2
          raise ArgumentError, "Timeline row cells must match the timeline day count"
        end
        return if cells.each_with_index.all? { |cell, index| cell.position == index + 1 }

        raise ArgumentError, "Timeline row cells must use consecutive one-based positions"
      end

      def call
        tag.div(**row_attributes) do
          safe_join([
            tag.div(summary, class: "panel-timeline__room-summary", role: "rowheader"),
            tag.div(class: "panel-timeline__row-track", role: "presentation") do
              safe_join(cells + segments)
            end
          ])
        end
      end

      private

      def row_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}

        attributes.merge(
          class: tw_merge("panel-timeline__row", @class, attributes.delete(:class)),
          role: "row",
          aria: { label: @accessible_label },
          data: data.merge(slot: "timeline-row")
        )
      end
    end
  end
end
