# frozen_string_literal: true

module StayView
  class ProjectRoom
    def self.call(room_type:, room_number:, bookings:, room_status:, room_blocks:, date_window:, capabilities:)
      new(room_type:, room_number:, bookings:, room_status:, room_blocks:, date_window:, capabilities:).call
    end

    def initialize(room_type:, room_number:, bookings:, room_status:, room_blocks:, date_window:, capabilities:)
      @room_type = room_type
      @room_number = room_number
      @bookings = bookings
      @room_status = room_status
      @room_blocks = room_blocks
      @date_window = date_window
      @capabilities = capabilities
    end

    def call
      status = ResolveCurrentRoomStatus.call(room_status: room_status, operational_date: date_window.operational_date)
      booking_segments = bookings.map do |booking|
        ProjectBooking.call(booking:, room_type_name: room_type.name, date_window:, capabilities:)
      end
      operational_segments = room_blocks.map { |block| project_block(block) }

      RoomRow.new(
        key: "#{room_type.id}:#{room_number}",
        dom_id: "stay_view_room_#{room_type.id}_#{room_number.to_s.gsub(/[^a-zA-Z0-9_-]/, "_")}",
        room_number: room_number,
        room_type_id: room_type.id,
        room_type_name: room_type.name,
        smoking_allowed: room_type.smoking_allowed,
        pets_allowed: room_type.pets_allowed,
        current_physical_status: status.physical_status,
        operational_flags: status.operational_flags,
        day_cells: build_day_cells(operational_segments),
        booking_segments: booking_segments,
        operational_segments: operational_segments,
        capabilities: capabilities
      )
    end

    private

    attr_reader :room_type, :room_number, :bookings, :room_status, :room_blocks, :date_window, :capabilities

    def build_day_cells(operational_segments)
      date_window.dates.map do |date|
        kinds = operational_segments.filter_map do |segment|
          segment.kind if segment.start_date <= date && date < segment.end_date
        end
        DayCell.new(date:, occupancies: ResolveOccupancy.call(date:, bookings:), operational_kinds: kinds)
      end
    end

    def project_block(block)
      exclusive_end = block.end_date + 1.day
      tracks = date_window.full_day_tracks(block.start_date, exclusive_end)
      label = block.block_type.to_s.humanize
      OperationalSegment.new(
        dom_id: "stay_view_room_block_#{block.id}",
        kind: block.block_type,
        label: label,
        start_date: block.start_date,
        end_date: exclusive_end,
        start_track: tracks.start_track,
        end_track: tracks.end_track,
        clipped_left: tracks.clipped_left?,
        clipped_right: tracks.clipped_right?,
        accessible_label: "#{label}, room #{room_number}, #{block.start_date.to_fs(:long)} to #{block.end_date.to_fs(:long)}: #{block.reason}",
        capabilities: capabilities
      )
    end
  end
end
