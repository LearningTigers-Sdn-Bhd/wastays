# frozen_string_literal: true

module HotelPortal
  module StayView
    class BookingBar < PanelsUI::BaseComponent
      STATUS_TONES = {
        pending: :neutral,
        confirmed: :primary,
        review_no_show: :warning,
        checked_in: :success,
        review_due_out: :warning,
        checkout_required: :warning,
        cancelled: :destructive,
        completed: :neutral,
        overbooked: :destructive,
        no_show: :destructive
      }.freeze

      def initialize(segment:, href: nil, class: nil, link_attributes: {}, **attributes)
        @segment = segment
        @href = href
        @class = binding.local_variable_get(:class)
        @link_attributes = link_attributes
        @attributes = attributes
      end

      def before_render
        unless @segment.is_a?(::StayView::BookingSegment)
          raise ArgumentError, "BookingBar requires a StayView::BookingSegment"
        end
      end

      def call
        render PanelsUI::Timeline::Segment.new(
          start_track: @segment.start_track,
          end_track: @segment.end_track,
          accessible_label: @segment.accessible_label,
          tone: STATUS_TONES.fetch(@segment.status, :neutral),
          emphasis: :solid,
          clipped_left: @segment.clipped_left?,
          clipped_right: @segment.clipped_right?,
          href: permitted_href,
          class: @class,
          link_attributes: @link_attributes,
          id: @segment.dom_id,
          **@attributes
        ) do
          tag.span(@segment.guest_label, class: "truncate")
        end
      end

      private

      def permitted_href
        @href if @href.present? && @segment.capabilities.view_booking?
      end
    end
  end
end
