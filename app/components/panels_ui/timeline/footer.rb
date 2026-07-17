# frozen_string_literal: true

module PanelsUI
  module Timeline
    class Footer < PanelsUI::BaseComponent
      renders_many :summaries

      def initialize(track_count:, label:, class: nil, **attributes)
        @track_count = track_count
        @label = label
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "Timeline footer label is required" if @label.blank?
        return if summaries.size == @track_count / 2

        raise ArgumentError, "Timeline footer summaries must match the timeline day count"
      end

      def call
        tag.div(**footer_attributes) do
          tag.div(class: "panel-timeline__footer-row", role: "row") do
            safe_join([
              tag.div(@label, class: "panel-timeline__footer-label", role: "rowheader"),
              summary_track
            ])
          end
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
              data: { slot: "timeline-footer-summary", position: index + 1 }
            )
          end)
        end
      end

      def footer_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}

        attributes.merge(
          class: tw_merge("panel-timeline__footer", @class, attributes.delete(:class)),
          role: "rowgroup",
          data: data.merge(slot: "timeline-footer")
        )
      end
    end
  end
end
