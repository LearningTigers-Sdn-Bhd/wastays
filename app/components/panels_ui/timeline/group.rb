# frozen_string_literal: true

module PanelsUI
  module Timeline
    class Group < PanelsUI::BaseComponent
      renders_many :rows, types: {
        standard: ->(**args) { Row.new(track_count: @track_count, **args) },
        component: ->(component:) { component }
      }
      renders_many :summaries

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
        return if summaries.empty? || summaries.size == @track_count / 2

        raise ArgumentError, "Timeline group summaries must match the timeline day count"
      end

      def call
        tag.section(**group_attributes) do
          safe_join([
            tag.div(class: "panel-timeline__group-heading", role: "row") do
              safe_join([
                tag.div(class: "panel-timeline__group-label", role: "rowheader") do
                  safe_join([
                    tag.span(@label),
                    (tag.span(@count, class: "panel-timeline__group-count", aria: { label: "#{@count} rooms" }) unless @count.nil?)
                  ].compact)
                end,
                (summary_track if summaries.any?)
              ].compact)
            end,
            safe_join(rows)
          ])
        end
      end

      private

      def summary_track
        tag.div(class: "panel-timeline__summary-track", role: "presentation") do
          safe_join(summaries.each_with_index.map do |summary, index|
            tag.div(
              summary,
              class: "panel-timeline__summary-cell",
              role: "cell",
              style: "grid-column: #{(index * 2) + 1} / span 2",
              data: { slot: "timeline-group-summary", position: index + 1 }
            )
          end)
        end
      end

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
