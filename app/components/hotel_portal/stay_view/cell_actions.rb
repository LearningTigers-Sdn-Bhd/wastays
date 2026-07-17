# frozen_string_literal: true

module HotelPortal
  module StayView
    class CellActions < PanelsUI::BaseComponent
      def initialize(room:, cell:, state:)
        @room = room
        @cell = cell
        @state = state
      end

      def before_render
        raise ArgumentError, "CellActions requires a StayView::RoomRow" unless @room.is_a?(::StayView::RoomRow)
        raise ArgumentError, "CellActions requires a StayView::DayCell" unless @cell.is_a?(::StayView::DayCell)
      end

      def call
        return if actions.empty?

        render PanelsUI::DropdownMenu.new(id:, placement: :bottom, class: "w-52") do |menu|
          menu.with_trigger(
            variant: :ghost,
            size: :icon_sm,
            aria_label: "Actions for room #{@room.room_number} on #{@cell.date.to_fs(:long)}",
            class: "panel-timeline__cell-action",
            data: { alignment: }
          ) do
            tag.span(class: "panel-timeline__cell-action-indicator", aria: { hidden: true }) do
              helpers.app_icon("plus", class: "size-3")
            end
          end
          actions.each do |action|
            menu.with_item(href: action.fetch(:href), data: action.fetch(:data)) do
              safe_join([
                helpers.app_icon(action.fetch(:icon), class: "size-4", aria: { hidden: true }),
                tag.span(action.fetch(:label))
              ])
            end
          end
        end
      end

      private

      def actions
        @actions ||= helpers.stay_view_cell_actions(@room, @cell, @state)
      end

      # A departure bar occupies the left half of the cell, so the trigger
      # stays in the free right half; a fully free cell centers it.
      def alignment
        @cell.occupancies.any? { |occupancy| occupancy.state == :departure } ? :end : :center
      end

      def id
        "#{@room.dom_id}-#{@cell.date.iso8601}-cell-actions"
      end
    end
  end
end
