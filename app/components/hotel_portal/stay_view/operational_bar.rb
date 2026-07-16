# frozen_string_literal: true

module HotelPortal
  module StayView
    class OperationalBar < PanelsUI::BaseComponent
      KIND_TONES = {
        maintenance: :warning,
        deep_cleaning: :info,
        renovation: :destructive,
        owner_use: :neutral,
        admin_hold: :warning
      }.freeze

      def initialize(segment:, class: nil, **attributes)
        @segment = segment
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def before_render
        unless @segment.is_a?(::StayView::OperationalSegment)
          raise ArgumentError, "OperationalBar requires a StayView::OperationalSegment"
        end
      end

      def call
        render PanelsUI::Timeline::Segment.new(
          start_track: @segment.start_track,
          end_track: @segment.end_track,
          accessible_label: @segment.accessible_label,
          tone: KIND_TONES.fetch(@segment.kind, :neutral),
          emphasis: :hatched,
          clipped_left: @segment.clipped_left?,
          clipped_right: @segment.clipped_right?,
          class: @class,
          id: @segment.dom_id,
          **@attributes
        ) do
          tag.span(@segment.label, class: "truncate")
        end
      end
    end
  end
end
