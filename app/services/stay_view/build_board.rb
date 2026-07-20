# frozen_string_literal: true

module StayView
  class BuildBoard
    EVENT_NAME = "stay_view.build_board"

    def self.call(hotel:, user:, start_date: nil, days: nil, view_mode: :timeline, filters: {}, now: Time.current, capabilities: nil)
      new(hotel:, user:, start_date:, days:, view_mode:, filters:, now:, capabilities:).call
    end

    def initialize(hotel:, user:, start_date:, days:, view_mode:, filters:, now:, capabilities:)
      @hotel = hotel
      @user = user
      @start_date = start_date
      @days = days
      @view_mode = view_mode
      @filters = filters
      @now = now
      @capabilities = capabilities
    end

    def call
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      resolved_capabilities = capabilities || BuildCapabilities.call(user:, hotel:)
      date_window = DateWindow.new(hotel:, start_date:, days:, view_mode:, now:)
      normalized_filters = FilterState.build(filters).for_view(date_window.view_mode)
      inventory = LoadInventory.call(
        hotel:,
        date_window:,
        capabilities: resolved_capabilities,
        rate_plan_id: normalized_filters.rate_plan_id
      )
      selected_rate_plan = inventory.rate_plan_options.find { |option| option.id == inventory.selected_rate_plan_id }
      applicable_room_types = applicable_room_types(inventory.room_types, selected_rate_plan)
      effective_room_type_id = normalized_filters.room_type_id if applicable_room_types.any? do |room_type|
        room_type.id == normalized_filters.room_type_id
      end
      effective_filters = normalized_filters.with(
        rate_plan_id: selected_rate_plan&.id,
        room_type_id: effective_room_type_id
      )
      projected_groups = project_groups(inventory, date_window, resolved_capabilities)
      if selected_rate_plan
        projected_groups = projected_groups.select { |group| group.room_type_id.in?(selected_rate_plan.room_type_ids) }.freeze
      end
      filtered_groups = ApplyFilters.call(
        room_groups: projected_groups,
        filters: effective_filters,
        hotel:,
        reference_date: date_window.start_date,
        operational_date: date_window.operational_date
      )
      groups = CalculateInventorySummaries.call(
        room_groups: filtered_groups,
        room_inventories: inventory.room_inventories,
        dates: date_window.dates,
        standard_rates: ResolveStandardRates.call(
          room_types: inventory.room_types,
          standard_rates: inventory.standard_rates,
          dates: date_window.dates,
          selected_rate_plan:
        )
      )
      footer_summaries = CalculateFooterSummaries.call(room_groups: groups, dates: date_window.dates)
      room_card_presentations = resolve_room_card_presentations(groups, date_window)
      counts = CalculateCounts.call(
        room_groups: groups,
        room_card_presentations:,
        reference_date: date_window.start_date
      )
      room_type_options = applicable_room_types.map { |room_type| RoomTypeOption.new(id: room_type.id, name: room_type.name) }
      board = Board.new(
        view_mode: date_window.view_mode,
        date_window:,
        room_groups: groups,
        footer_summaries:,
        room_type_options:,
        rate_plan_options: inventory.rate_plan_options,
        status_counts: counts,
        filters: effective_filters,
        capabilities: resolved_capabilities,
        room_card_presentations:
      )
      instrument(board, started_at)
      board
    end

    private

    attr_reader :hotel, :user, :start_date, :days, :view_mode, :filters, :now, :capabilities

    def applicable_room_types(room_types, selected_rate_plan)
      return room_types unless selected_rate_plan

      room_types.select { |room_type| room_type.id.in?(selected_rate_plan.room_type_ids) }.freeze
    end

    def project_groups(inventory, date_window, capabilities)
      bookings = inventory.bookings.group_by { |record| [ record.room_type_id, record.room_number ] }
      statuses = inventory.room_statuses.index_by { |record| [ record.room_type_id, record.room_number ] }
      blocks = inventory.room_blocks.group_by { |record| [ record.room_type_id, record.room_number ] }
      housekeeping_alerts = inventory.housekeeping_alerts.group_by { |record| [ record.room_type_id, record.room_number ] }

      inventory.room_types.map do |room_type|
        rooms = room_type.room_numbers.map do |room_number|
          key = [ room_type.id, room_number ]
          ProjectRoom.call(
            room_type:, room_number:, bookings: bookings.fetch(key, EMPTY), room_status: statuses[key],
            room_blocks: blocks.fetch(key, EMPTY), housekeeping_alerts: housekeeping_alerts.fetch(key, EMPTY),
            group_rooms: inventory.group_rooms, financial_signals: inventory.financial_signals,
            date_window:, capabilities:
          )
        end
        RoomGroup.new(room_type_id: room_type.id, name: room_type.name, rooms: rooms)
      end.freeze
    end

    def resolve_room_card_presentations(groups, date_window)
      groups.flat_map(&:rooms).to_h do |room|
        [
          room.key,
          ResolveRoomCardSlots.call(
            hotel:,
            room:,
            date: date_window.start_date,
            operational_date: date_window.operational_date
          )
        ]
      end
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
