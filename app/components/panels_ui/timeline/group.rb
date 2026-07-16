# frozen_string_literal: true

module PanelsUI
  module Timeline
    class Group < PanelsUI::BaseComponent
      renders_many :rows, types: {
        standard: ->(**args) { Row.new(track_count: @track_count, **args) },
        component: ->(component:) { component }
      }

      def with_row(...) = with_row_standard(...)
      def with_custom_row(...) = with_row_component(...)

      def initialize(track_count:, label:, count: nil, class: nil, **attributes)
        @track_count = track_count
        @label = label
        @count = count
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "Timeline group label is required" if @label.blank?
      end

      def call
        tag.section(**group_attributes) do
          safe_join([
            tag.div(class: "panel-timeline__group-heading", role: "row") do
              tag.div(class: "panel-timeline__group-label", role: "columnheader") do
                safe_join([
                  tag.span(@label),
                  (tag.span(@count, class: "panel-timeline__group-count", aria: { label: "#{@count} rooms" }) unless @count.nil?)
                ].compact)
              end
            end,
            safe_join(rows)
          ])
        end
      end

      private

      def group_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}

        attributes.merge(
          class: tw_merge("panel-timeline__group", @class, attributes.delete(:class)),
          role: "rowgroup",
          data: data.merge(slot: "timeline-group")
        )
      end
    end
  end
end
