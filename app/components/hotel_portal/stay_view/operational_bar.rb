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

      def initialize(segment:, href: nil, id: nil, class: nil, link_attributes: {}, **attributes)
        @segment = segment
        @href = href
        @id = id
        @class = binding.local_variable_get(:class)
        @link_attributes = link_attributes
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
          href: @href,
          link_attributes: @link_attributes,
          class: @class,
          id: @id.presence || @segment.dom_id,
          **@attributes
        ) do
          bar_content
        end
      end

      private

      # The kind keeps its place at the head of the bar; the reason follows it
      # in a lighter weight and gives way first when the bar is too narrow for
      # both, so a long reason never squeezes out the label.
      def bar_content
        safe_join([
          tag.span(@segment.label, class: "shrink-0 truncate"),
          reason
        ].compact)
      end

      def reason
        return if @segment.reason.blank?

        tag.span(
          @segment.reason,
          class: "min-w-0 truncate font-normal opacity-80",
          data: { slot: "stay-view-operational-reason" }
        )
      end
    end
  end
end
