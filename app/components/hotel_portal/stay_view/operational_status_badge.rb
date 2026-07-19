# frozen_string_literal: true

module HotelPortal
  module StayView
    class OperationalStatusBadge < PanelsUI::BaseComponent
      def initialize(room:, status:, reference_date:)
        @room = room
        @status = status.to_sym
        @reference_date = reference_date.to_date
      end

      def before_render
        raise ArgumentError, "OperationalStatusBadge requires a StayView::RoomRow" unless @room.is_a?(::StayView::RoomRow)
      end

      def call
        presentation = OperationalCounts::PRESENTATION.fetch(@status)
        render PanelsUI::Badge.new(
          label: presentation.fetch(:label),
          variant: presentation.fetch(:variant),
          size: :sm,
          indicator: true,
          aria: { label: "Operational state: #{presentation.fetch(:label)}" },
          data: { slot: "stay-view-operational-status", status: @status, reference_date: @reference_date.iso8601 }
        )
      end
    end
  end
end
