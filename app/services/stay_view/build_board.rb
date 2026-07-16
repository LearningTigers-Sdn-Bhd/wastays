# frozen_string_literal: true

module StayView
  class BuildBoard
    EVENT_NAME = "stay_view.build_board"

    def self.call(hotel:, user:, start_date: nil, days: nil, view_mode: :timeline, filters: {}, now: Time.current)
      new(hotel:, user:, start_date:, days:, view_mode:, filters:, now:).call
    end

    def initialize(hotel:, user:, start_date:, days:, view_mode:, filters:, now:)
      @hotel = hotel
      @user = user
      @start_date = start_date
      @days = days
      @view_mode = view_mode
      @filters = filters
      @now = now
    end

    def call
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      capabilities = BuildCapabilities.call(user:, hotel:)
      date_window = DateWindow.new(hotel:, start_date:, days:, view_mode:, now:)
      inventory = LoadInventory.call(hotel:, date_window:, capabilities:)
      normalized_filters = FilterState.build(filters)
      groups = ApplyFilters.call(room_groups: project_groups(inventory, date_window, capabilities), filters: normalized_filters)
      counts = CalculateCounts.call(room_groups: groups)
      board = Board.new(view_mode: date_window.view_mode, date_window:, room_groups: groups, status_counts: counts, filters: normalized_filters, capabilities:)
      instrument(board, started_at)
      board
    end

    private

    attr_reader :hotel, :user, :start_date, :days, :view_mode, :filters, :now

    def project_groups(inventory, date_window, capabilities)
      bookings = inventory.bookings.group_by { |record| [ record.room_type_id, record.room_number ] }
      statuses = inventory.room_statuses.index_by { |record| [ record.room_type_id, record.room_number ] }
      blocks = inventory.room_blocks.group_by { |record| [ record.room_type_id, record.room_number ] }

      inventory.room_types.map do |room_type|
        rooms = room_type.room_numbers.map do |room_number|
          key = [ room_type.id, room_number ]
          ProjectRoom.call(
            room_type:, room_number:, bookings: bookings.fetch(key, EMPTY), room_status: statuses[key],
            room_blocks: blocks.fetch(key, EMPTY), date_window:, capabilities:
          )
        end
        RoomGroup.new(room_type_id: room_type.id, name: room_type.name, rooms: rooms)
      end.freeze
    end

    def instrument(board, started_at)
      rows = board.room_groups.flat_map(&:rooms)
      ActiveSupport::Notifications.instrument(
        EVENT_NAME,
        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(2),
        row_count: rows.size,
        segment_count: rows.sum { |row| row.booking_segments.size },
        operational_segment_count: rows.sum { |row| row.operational_segments.size }
      )
    end

    EMPTY = [].freeze
  end
end
