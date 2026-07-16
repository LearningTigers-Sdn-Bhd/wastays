# frozen_string_literal: true

module HotelPortal
  module StayView
    class TimelineRow < PanelsUI::BaseComponent
      def initialize(room:, state:)
        @room = room
        @state = state
      end

      def before_render
        raise ArgumentError, "TimelineRow requires a StayView::RoomRow" unless @room.is_a?(::StayView::RoomRow)
      end

      def call
        render row_component
      end

      private

      def row_component
        row = PanelsUI::Timeline::Row.new(
          track_count: @state.date_window.days * 2,
          accessible_label: "Room #{@room.room_number}, #{@room.room_type_name}",
          id: @room.dom_id,
          data: {
            "stay-view--interaction-target": "row",
            room_type_id: @room.room_type_id,
            room_number: @room.room_number
          }
        )
        row.with_summary do
          render RoomSummary.new(room: @room, actions: helpers.stay_view_timeline_menu_actions(@room, @state))
        end
        add_cells(row)
        add_booking_segments(row)
        add_operational_segments(row)
        row
      end

      def add_cells(row)
        @room.day_cells.each_with_index do |cell, index|
          row.with_cell(
            position: index + 1,
            accessible_label: cell_label(cell),
            current: cell.date == @state.date_window.operational_date,
            data: {
              "stay-view--interaction-target": "cell",
              date: cell.date.iso8601
            }
          ) do
            add_booking_link(cell)
          end
        end
      end

      def add_booking_segments(row)
        @room.booking_segments.each do |segment|
          row.with_segment do
            render BookingBar.new(
              segment:,
              href: helpers.stay_view_booking_path(segment.booking_id, return_to: return_to),
              link_attributes: { data: helpers.stay_view_action_data },
              interaction: interaction_for(segment)
            )
          end
        end
      end

      def add_operational_segments(row)
        @room.operational_segments.each do |segment|
          row.with_segment { render OperationalBar.new(segment:) }
        end
      end

      def add_booking_link(cell)
        return unless @room.capabilities.create_booking?
        return unless cell.occupancies.one? && cell.occupancies.first.state == :available
        return unless cell.operational_kinds.empty?

        helpers.link_to(
          helpers.hotel_booking_transaction_new_booking_path(
            helpers.current_hotel,
            check_in: cell.date,
            check_out: cell.date + 1.day,
            room_type_id: @room.room_type_id,
            room_number: @room.room_number,
            return_to:
          ),
          class: "panel-timeline__cell-action",
          aria: { label: "Add booking for room #{@room.room_number} on #{cell.date.to_fs(:long)}" },
          data: helpers.stay_view_action_data
        ) do
          helpers.app_icon "plus", class: "size-3", aria: { hidden: true }
        end
      end

      def interaction_for(segment)
        common = { return_to:, source: "stay_view", proposal: "pointer" }
        {
          room_type_id: @room.room_type_id,
          room_number: @room.room_number,
          move_url: (helpers.edit_hotel_stay_view_booking_move_path(helpers.current_hotel, segment.booking_id, common) if segment.capabilities.move_booking?),
          dates_url: (helpers.edit_hotel_stay_view_booking_dates_path(helpers.current_hotel, segment.booking_id, common) if segment.capabilities.change_dates?)
        }.compact
      end

      def cell_label(cell)
        occupancies = cell.occupancies.map { |occupancy| helpers.stay_view_occupancy_label(occupancy) }.to_sentence
        "Room #{@room.room_number}, #{helpers.stay_view_date_label(cell.date)}, #{occupancies}"
      end

      def return_to
        @return_to ||= @state.return_path(helpers.current_hotel)
      end
    end
  end
end
