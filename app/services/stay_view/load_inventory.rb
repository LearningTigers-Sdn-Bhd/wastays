# frozen_string_literal: true

module StayView
  class LoadInventory
    def self.call(hotel:, date_window:, capabilities:, rate_plan_id: nil)
      new(hotel:, date_window:, capabilities:, rate_plan_id:).call
    end

    def initialize(hotel:, date_window:, capabilities:, rate_plan_id: nil)
      @hotel = hotel
      @date_window = date_window
      @capabilities = capabilities
      @requested_rate_plan_id = Integer(rate_plan_id, exception: false)
    end

    def call
      bookings = load_bookings
      Inventory.new(
        room_types: load_room_types,
        bookings:,
        group_rooms: load_group_rooms(bookings.filter_map(&:group_booking_id).uniq),
        room_statuses: load_room_statuses,
        room_blocks: load_room_blocks,
        housekeeping_alerts: load_housekeeping_alerts,
        room_inventories: load_room_inventories,
        standard_rates: load_standard_rates,
        financial_signals: load_financial_signals(bookings),
        rate_plan_options: load_rate_plan_options,
        selected_rate_plan_id:,
        room_group_assignments: room_groups.assignments,
        room_group_options: room_groups.options
      )
    end

    private

    attr_reader :hotel, :date_window, :capabilities, :requested_rate_plan_id

    # Room-group membership lives on `rooms`, but room enumeration stays on the
    # room type's JSON list until Milestone 6. The two are joined by number.
    def room_groups
      @room_groups ||= ::Rooms::GroupAssignmentsQuery.call(hotel:)
    end

    def load_room_types
      base_price_column = capabilities.view_rates? ? :base_price : Arel.sql("NULL")
      @room_types ||= hotel.room_types.order(:name, :id)
        .pluck(:id, :name, :room_numbers, :smoking_allowed, :pets_allowed, base_price_column)
        .map do |id, name, room_numbers, smoking_allowed, pets_allowed, base_price|
          master_plan_id, rate_currency = load_master_plans[id]
          rate_currency = rate_currency.presence || hotel.default_currency.presence || "MYR" if capabilities.view_rates?
          RoomTypeRecord.new(
            id:, name:, room_numbers:, smoking_allowed:, pets_allowed:, base_price:,
            master_rate_plan_id: master_plan_id, rate_currency:
          )
        end
    end

    def load_master_plans
      return {} unless capabilities.view_rates?

      @master_plans ||= load_rate_plan_rows.each_with_object({}) do |row, result|
        room_type_id, rate_plan_id, _rate_plan_name, currency = row
        result[room_type_id] ||= [ rate_plan_id, currency ]
      end
    end

    def load_standard_rates
      return [] unless capabilities.view_rates?

      selected = selected_rate_plan
      scope = if selected
        RoomRate.where(room_type_id: selected.room_type_ids, rate_plan_id: selected.id)
      else
        room_type_ids = load_room_types.map(&:id)
        master_plan_ids = load_room_types.filter_map(&:master_rate_plan_id)
        RoomRate.where(room_type_id: room_type_ids, rate_plan_id: [ nil, *master_plan_ids ])
      end

      scope.where(date: date_window.start_date...date_window.end_date)
        .order(:room_type_id, :date, :rate_plan_id, :currency)
        .pluck(:room_type_id, :rate_plan_id, :date, :price, :currency)
        .map do |values|
          StandardRateRecord.new(**%i[room_type_id rate_plan_id date price currency].zip(values).to_h)
        end
    end

    def load_rate_plan_options
      return [] unless capabilities.view_rates?

      @rate_plan_options ||= load_rate_plan_rows
        .group_by { |row| row[1] }
        .map do |rate_plan_id, rows|
          _room_type_id, _id, name, currency = rows.first
          room_type_ids = rows.map(&:first)
          room_type_names = rows.map { |row| row[4] }
          scope_label = room_type_names.one? ? room_type_names.first : "#{room_type_names.size} room types"
          RatePlanOption.new(
            id: rate_plan_id,
            name:,
            currency:,
            room_type_ids:,
            room_type_names:,
            label: "#{name} — #{scope_label}"
          )
        end
        .sort_by { |option| [ option.name.downcase, option.id ] }
        .freeze
    end

    def load_rate_plan_rows
      return [] unless capabilities.view_rates?

      @rate_plan_rows ||= RoomTypeRatePlan.joins(:rate_plan, :room_type)
        .where(
          room_types: { hotel_id: hotel.id },
          rate_plans: { hotel_id: hotel.id, archived_at: nil, kind: RatePlan.kinds_for(:staff) }
        )
        .order("room_type_rate_plans.room_type_id", "room_type_rate_plans.rate_plan_id")
        .pluck(
          "room_type_rate_plans.room_type_id",
          "room_type_rate_plans.rate_plan_id",
          "rate_plans.name",
          "rate_plans.currency",
          "room_types.name"
        )
    end

    def selected_rate_plan
      @selected_rate_plan ||= load_rate_plan_options.find { |option| option.id == requested_rate_plan_id }
    end

    def selected_rate_plan_id = selected_rate_plan&.id

    def load_financial_signals(bookings)
      return {} unless capabilities.view_financial_status?

      ResolveFinancialSignals.call(hotel:, bookings:)
    end

    def load_bookings
      guest_column = capabilities.view_booking? ? "bookings.guest_name" : Arel.sql("NULL")
      primary_guest_column = capabilities.view_booking? ? primary_guest_name_column : Arel.sql("NULL")
      group_reference_column = capabilities.view_booking? ? "group_bookings.reservation_reference" : Arel.sql("NULL")
      group_name_column = capabilities.view_booking? ? "group_bookings.name" : Arel.sql("NULL")
      adults_column = capabilities.view_booking? ? "bookings.adults" : Arel.sql("NULL")
      children_column = capabilities.view_booking? ? "bookings.children" : Arel.sql("NULL")
      boat_in_column = load_boat_information? ? primary_guest_attribute_column(:boat_in_at) : Arel.sql("NULL")
      boat_out_column = load_boat_information? ? primary_guest_attribute_column(:boat_out_at) : Arel.sql("NULL")
      primary_guest_id = capabilities.view_booking? ? primary_guest_id_column : Arel.sql("NULL")
      columns = [
        "booking_rooms.id", "bookings.id", "booking_rooms.room_type_id", "booking_rooms.room_number",
        "bookings.status", guest_column, primary_guest_column, "bookings.check_in", "bookings.check_out",
        "bookings.checked_in_at", "bookings.checked_out_at", "bookings.group_booking_id",
        group_reference_column, group_name_column, "bookings.group_position", "bookings.source",
        adults_column, children_column, boat_in_column, boat_out_column, primary_guest_id
      ]

      scope = BookingRoom.joins(:booking)
        .left_joins(booking: :group_booking)
        .where(bookings: { hotel_id: hotel.id, status: visible_booking_statuses })
        .where.not(room_number: [ nil, "" ])
      # Filter on the effective occupancy window (actual timestamps when the
      # guest has physically checked in/out, scheduled dates otherwise) so late
      # checkouts and early arrivals surface in both the rooms and timeline
      # views instead of only the schedule-based one.
      scope = scope.where(
        "COALESCE(bookings.checked_in_at, bookings.check_in) < :window_end AND " \
        "COALESCE(bookings.checked_out_at, bookings.check_out) >= :window_start",
        window_end: date_window.window_end_at,
        window_start: date_window.window_start_at
      )

      rows = scope.pluck(*columns)
      guest_contexts = load_guest_contexts(rows.filter_map { |row| row[20] }.uniq)

      rows.map do |booking_room_id, booking_id, room_type_id, room_number, status, guest_name, primary_guest_name, check_in, check_out,
                  checked_in_at, checked_out_at, group_booking_id, group_reservation_number, group_name, group_position, source,
                  adults, children, boat_in_at, boat_out_at, primary_guest_id|
          guest_context = guest_contexts[primary_guest_id]
          check_in_at = check_in.in_time_zone(date_window.time_zone_name)
          check_out_at = check_out.in_time_zone(date_window.time_zone_name)
          actual_check_in_at = checked_in_at&.in_time_zone(date_window.time_zone_name)
          actual_check_out_at = checked_out_at&.in_time_zone(date_window.time_zone_name)
          BookingRecord.new(
            booking_room_id: booking_room_id,
            booking_id: booking_id,
            room_type_id: room_type_id,
            room_number: room_number.to_s.freeze,
            status: status.to_sym,
            guest_name: guest_name&.to_s&.freeze,
            primary_guest_name: primary_guest_name&.to_s&.freeze,
            check_in: check_in_at.to_date,
            check_out: check_out_at.to_date,
            check_in_at:,
            check_out_at:,
            actual_check_in: actual_check_in_at&.to_date,
            actual_check_out: actual_check_out_at&.to_date,
            actual_check_in_at:,
            actual_check_out_at:,
            group_booking_id:,
            group_reference: group_reference(group_reservation_number),
            group_name:,
            group_position:,
            source:,
            adults:,
            children:,
            boat_in_at:,
            boat_out_at:,
            vip: guest_context&.fetch(:vip, false) || false,
            blacklisted: guest_context&.fetch(:blacklisted, false) || false,
            repeat: guest_context&.fetch(:completed_booking_count, 0).to_i > (status.to_sym == :completed ? 1 : 0)
          )
        end
    end

    def load_guest_contexts(guest_ids)
      return {} if guest_ids.empty? || !capabilities.view_booking?

      completed_booking_counts = BookingGuest.joins(:booking)
        .where(role: "primary", guest_id: guest_ids, bookings: { hotel_id: hotel.id, status: "completed" })
        .group(:guest_id)
        .count

      Guest.where(id: guest_ids).select(:id, :vip, :blacklisted, :created_by_hotel_id, :metadata).each_with_object({}) do |guest, result|
        result[guest.id] = {
          vip: guest.vip?,
          blacklisted: guest.blacklisted_at?(hotel),
          completed_booking_count: completed_booking_counts.fetch(guest.id, 0)
        }.freeze
      end.freeze
    end

    def primary_guest_name_column
      primary_guest = BookingGuest.joins(:guest)
        .where("booking_guests.booking_id = bookings.id", role: "primary")
        .select("COALESCE(booking_guests.name_snapshot, guests.name)")
        .limit(1)
      Arel.sql("COALESCE((#{primary_guest.to_sql}), bookings.guest_name)")
    end

    def primary_guest_id_column
      primary_guest = BookingGuest
        .where("booking_guests.booking_id = bookings.id", role: "primary")
        .select(:guest_id)
        .limit(1)
      Arel.sql("(#{primary_guest.to_sql})")
    end

    def primary_guest_attribute_column(attribute)
      primary_guest = BookingGuest
        .where("booking_guests.booking_id = bookings.id", role: "primary")
        .select(BookingGuest.arel_table[attribute])
        .limit(1)
      Arel.sql("(#{primary_guest.to_sql})")
    end

    def load_boat_information?
      capabilities.view_booking? && hotel.allow_boat_information?
    end

    def load_group_rooms(group_booking_ids)
      return {} if group_booking_ids.empty? || !capabilities.view_booking?

      BookingRoom.joins(:booking, :room_type)
        .where(bookings: { hotel_id: hotel.id, group_booking_id: group_booking_ids, status: visible_booking_statuses })
        .where.not(room_number: [ nil, "" ])
        .order("bookings.group_booking_id", "bookings.group_position", "bookings.id", "booking_rooms.id")
        .pluck("bookings.group_booking_id", "bookings.id", "booking_rooms.id", "bookings.group_position", "booking_rooms.room_number", "room_types.name")
        .map do |group_booking_id, booking_id, booking_room_id, group_position, room_number, room_type_name|
          GroupRoomRecord.new(group_booking_id:, booking_id:, booking_room_id:, group_position:, room_number:, room_type_name:)
        end
        .group_by(&:group_booking_id)
    end

    def group_reference(reference) = reference

    def visible_booking_statuses
      Booking::OCCUPYING_STATUSES
    end

    def load_room_statuses
      note_column = capabilities.view_room_readiness? ? :notes : Arel.sql("NULL")
      priority_note_column = capabilities.view_room_readiness? ? :priority_note : Arel.sql("NULL")
      hotel.room_statuses.pluck(
        :room_type_id, :room_number, :status, :priority, :dnd, :dnd_date, note_column, priority_note_column
      ).map do |values|
        RoomStatusRecord.new(
          room_type_id: values[0], room_number: values[1].to_s.freeze, status: values[2].to_sym,
          priority: values[3], dnd: values[4], dnd_date: values[5], status_note: values[6], priority_note: values[7]
        )
      end
    end

    def load_room_blocks
      hotel.room_blocks.where(completed_at: nil)
        .where("start_date < ? AND end_date >= ?", date_window.end_date, date_window.start_date)
        .pluck(:id, :room_type_id, :room_number, :block_type, :reason, :start_date, :end_date)
        .map do |values|
          RoomBlockRecord.new(
            id: values[0], room_type_id: values[1], room_number: values[2].to_s.freeze,
            block_type: values[3].to_sym, reason: values[4].to_s.freeze,
            start_date: values[5], end_date: values[6]
          )
        end
    end

    def load_room_inventories
      RoomInventory.where(room_type_id: load_room_types.map(&:id), date: date_window.start_date...date_window.end_date)
        .order(:room_type_id, :date)
        .pluck(:room_type_id, :date, :quantity, :status, :available_room_numbers)
        .map do |values|
          RoomInventoryRecord.new(
            **%i[room_type_id date quantity status available_room_numbers].zip(values).to_h
          )
        end
    end

    def load_housekeeping_alerts
      configured_rooms = load_room_keys
      rows = hotel_owned_housekeeping_rows + legacy_booking_owned_housekeeping_rows

      rows.filter_map do |values|
        request_id, room_type_id, request_room_number, booking_room_type_id, booking_room_number,
          details, status, requested_at, created_at, metadata = values
        room_number = request_room_number.presence || booking_room_number.presence
        resolved_room_type_id = room_type_id || booking_room_type_id
        key = [ resolved_room_type_id, room_number.to_s ]
        next unless room_number.present? && configured_rooms.include?(key)

        metadata = metadata.to_h
        HousekeepingAlertRecord.new(
          request_id:,
          room_type_id: resolved_room_type_id,
          room_number:,
          details:,
          status:,
          requested_at: (requested_at || created_at).in_time_zone(date_window.time_zone_name),
          assigned_to_id: metadata["assigned_to"],
          assigned_to_name: metadata["assigned_to_name"],
          assignment_history: normalize_assignment_history(metadata["assignment_history"])
        )
      end.uniq { |record| [ record.request_id, record.room_type_id, record.room_number ] }
        .sort_by { |record| [ -record.requested_at.to_i, record.request_id ] }
    end

    def load_room_keys
      load_room_types.flat_map do |room_type|
        room_type.room_numbers.map { |room_number| [ room_type.id, room_number ] }
      end.to_set
    end

    def hotel_owned_housekeeping_rows
      housekeeping_scope
        .where(housekeeping_requests: { hotel_id: hotel.id })
        .pluck(*housekeeping_columns)
    end

    def legacy_booking_owned_housekeeping_rows
      housekeeping_scope
        .where(housekeeping_requests: { hotel_id: nil })
        .where(bookings: { hotel_id: hotel.id })
        .pluck(*housekeeping_columns)
    end

    def housekeeping_scope
      HousekeepingRequest.left_joins(booking: :booking_rooms)
        .where(archived_at: nil, status: %w[new assigned in_progress])
    end

    def housekeeping_columns
      [
        "housekeeping_requests.id", "housekeeping_requests.room_type_id", "housekeeping_requests.room_number",
        "booking_rooms.room_type_id", "booking_rooms.room_number", "housekeeping_requests.request_details",
        "housekeeping_requests.status", "housekeeping_requests.requested_at", "housekeeping_requests.created_at",
        "housekeeping_requests.metadata"
      ]
    end

    def normalize_assignment_history(history)
      Array(history).filter_map do |raw_event|
        event = raw_event.respond_to?(:to_h) ? raw_event.to_h.stringify_keys : {}
        assigned_to_name = event["assigned_to_name"].presence
        timestamp = parse_assignment_timestamp(event["timestamp"])
        next if assigned_to_name.blank? || timestamp.nil?

        HousekeepingAssignmentEventRecord.new(
          assigned_to_name:,
          assigned_by_name: event["assigned_by_name"].presence || "System",
          timestamp:
        )
      end.last(5).reverse
    end

    def parse_assignment_timestamp(value)
      Time.iso8601(value.to_s).in_time_zone(date_window.time_zone_name)
    rescue ArgumentError
      nil
    end
  end
end
