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
            stay_view_room: true,
            room_type_id: @room.room_type_id,
            room_number: @room.room_number,
            create_url: create_url
          }.compact
        )
        row.with_summary do
          render RoomSummary.new(room: @room, state: @state)
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
              date: cell.date.iso8601,
              **selection_data(cell)
            }
          ) do
            add_cell_actions(cell)
          end
        end
      end

      def add_booking_segments(row)
        @room.booking_segments.each do |segment|
          row.with_segment do
            render BookingBar.new(
              segment:,
              href: helpers.stay_view_booking_path(segment.booking_id, return_to:, source: "stay_view"),
              link_attributes: { data: helpers.stay_view_booking_action_data },
              interaction: interaction_for(segment)
            )
          end
        end
      end

      def add_operational_segments(row)
        @room.operational_segments.each do |segment|
          row.with_segment do
            render OperationalBar.new(
              segment:,
              href: room_block_href(segment),
              link_attributes: { data: helpers.stay_view_action_data }
            )
          end
        end
      end

      # The same sheet the Rooms view opens, so a block can be finished or
      # removed from the timeline rather than only from a room card.
      def room_block_href(segment)
        return unless segment.capabilities.manage_room_blocks?
        return if segment.room_block_id.blank?

        helpers.edit_hotel_stay_view_room_block_path(
          helpers.current_hotel,
          segment.room_block_id,
          return_to:,
          source: "stay_view"
        )
      end

      def add_cell_actions(cell)
        return unless free?(cell)

        render CellActions.new(room: @room, cell:, state: @state)
      end

      # A night nobody has taken and no block covers. The cell menu and the
      # drag-to-select range both hang off this one answer, so the two can
      # never offer a room the other would refuse.
      def free?(cell)
        return false if cell.occupancies.any? { |occupancy| occupancy.state.in?(%i[arrival occupied]) }

        cell.operational_kinds.empty?
      end

      # Past nights are left to the cell menu, which sends them to the
      # backdated check-in flow rather than the ordinary booking sheet.
      def selection_data(cell)
        return {} if create_url.blank?
        return {} unless free?(cell)
        return {} if cell.date < @state.date_window.operational_date

        { selectable: "true", action: "pointerdown->stay-view--interaction#startSelection" }
      end

      # The dates come from the drag; everything else about the stay is fixed
      # by the row it was drawn on.
      def create_url
        return @create_url if defined?(@create_url)

        @create_url =
          if @room.capabilities.create_booking?
            helpers.hotel_booking_action_quick_booking_path(
              helpers.current_hotel,
              room_type_id: @room.room_type_id,
              room_number: @room.room_number,
              source: "stay_view",
              return_to:
            )
          end
      end

      def interaction_for(segment)
        common = { return_to:, source: "stay_view", proposal: "pointer" }
        {
          room_type_id: @room.room_type_id,
          room_number: @room.room_number,
          move_url: (helpers.hotel_booking_action_edit_room_path(helpers.current_hotel, segment.booking_id, common.merge(proposal_kind: "move")) if segment.capabilities.move_booking?),
          dates_url: (helpers.hotel_booking_action_edit_dates_path(helpers.current_hotel, segment.booking_id, common.merge(proposal_kind: "dates")) if segment.capabilities.change_dates?)
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
