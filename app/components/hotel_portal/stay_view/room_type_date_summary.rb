# frozen_string_literal: true

module HotelPortal
  module StayView
    class RoomTypeDateSummary < PanelsUI::BaseComponent
      def initialize(summary:, room_type_name:, view_rates:)
        @summary = summary
        @room_type_name = room_type_name.to_s
        @view_rates = view_rates
      end

      def before_render
        return if @summary.is_a?(::StayView::InventoryDateSummary) && @room_type_name.present?

        raise ArgumentError, "RoomTypeDateSummary requires an inventory summary and room type name"
      end

      def call
        tag.div(class: "flex flex-col items-center justify-center gap-1") do
          safe_join([
            render(InventoryBadge.new(summary: @summary, room_type_name: @room_type_name)),
            render(NightlyRate.new(
              summary: @summary,
              room_type_name: @room_type_name,
              view_rates: @view_rates,
              context: :timeline
            ))
          ])
        end
      end
    end
  end
end
