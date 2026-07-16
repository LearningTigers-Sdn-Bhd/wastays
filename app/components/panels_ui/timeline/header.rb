# frozen_string_literal: true

module PanelsUI
  module Timeline
    class Header < PanelsUI::BaseComponent
      DateColumn = Data.define(:label, :metadata, :accessible_label, :current)

      def initialize(track_count:, room_label:, dates:, class: nil, **attributes)
        @track_count = track_count
        @room_label = room_label
        @dates = Array(dates).map { |date| normalize_date(date) }.freeze
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        raise ArgumentError, "Timeline header room_label is required" if @room_label.blank?
        unless @dates.size == @track_count / 2
          raise ArgumentError, "Timeline header dates must match the timeline day count"
        end
      end

      def call
        tag.div(**header_attributes) do
          tag.div(class: "panel-timeline__header-row", role: "row") do
            safe_join([
              tag.div(@room_label, class: "panel-timeline__room-header", role: "columnheader"),
              tag.div(class: "panel-timeline__date-track", role: "presentation") do
                safe_join(@dates.each_with_index.map { |date, index| date_column(date, index) })
              end
            ])
          end
        end
      end

      private

      def normalize_date(value)
        source = value.respond_to?(:to_h) ? value.to_h.symbolize_keys : { label: value.to_s }
        label = source[:label].to_s
        DateColumn.new(
          label: label,
          metadata: source[:metadata].presence&.to_s,
          accessible_label: source[:accessible_label].presence&.to_s || [ label, source[:metadata] ].compact.join(" "),
          current: ActiveModel::Type::Boolean.new.cast(source[:current])
        )
      end

      def header_attributes
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}

        attributes.merge(
          class: tw_merge("panel-timeline__header", @class, attributes.delete(:class)),
          role: "rowgroup",
          data: data.merge(slot: "timeline-header")
        )
      end

      def date_column(date, index)
        tag.div(
          class: "panel-timeline__date",
          role: "columnheader",
          aria: { label: date.accessible_label },
          style: "grid-column: #{(index * 2) + 1} / span 2",
          data: { current: ("true" if date.current) }
        ) do
          safe_join([
            tag.span(date.label, class: "panel-timeline__date-label"),
            (tag.span(date.metadata, class: "panel-timeline__date-metadata") if date.metadata)
          ].compact)
        end
      end
    end
  end
end
