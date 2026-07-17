# frozen_string_literal: true

module StayView
  class LoadInventory
    def self.call(hotel:, date_window:, capabilities:)
      new(hotel:, date_window:, capabilities:).call
    end

    def initialize(hotel:, date_window:, capabilities:)
      @hotel = hotel
      @date_window = date_window
      @capabilities = capabilities
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
        standard_rates: load_standard_rates
      )
    end

    private

    attr_reader :hotel, :date_window, :capabilities

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

      @master_plans ||= RoomTypeRatePlan.joins(:rate_plan)
        .where(room_type_id: hotel.room_types.select(:id))
        .order(:room_type_id, :rate_plan_id)
        .pluck(:room_type_id, :rate_plan_id, "rate_plans.currency")
        .each_with_object({}) do |(room_type_id, rate_plan_id, currency), result|
          result[room_type_id] ||= [ rate_plan_id, currency ]
        end
    end

    def load_standard_rates
      return [] unless capabilities.view_rates?

      room_type_ids = load_room_types.map(&:id)
      master_plan_ids = load_room_types.filter_map(&:master_rate_plan_id)
      RoomRate.where(
        room_type_id: room_type_ids,
        rate_plan_id: [ nil, *master_plan_ids ],
        date: date_window.start_date...date_window.end_date
      ).order(:room_type_id, :date, :rate_plan_id, :currency)
        .pluck(:room_type_id, :rate_plan_id, :date, :price, :currency)
        .map do |values|
          StandardRateRecord.new(**%i[room_type_id rate_plan_id date price currency].zip(values).to_h)
        end
    end

    def load_bookings
      guest_column = capabilities.view_booking? ? "bookings.guest_name" : Arel.sql("NULL")
      primary_guest_column = capabilities.view_booking? ? primary_guest_name_column : Arel.sql("NULL")
      group_reference_column = capabilities.view_booking? ? "group_bookings.reservation_number" : Arel.sql("NULL")
      group_name_column = capabilities.view_booking? ? "group_bookings.name" : Arel.sql("NULL")
      columns = [
        "booking_rooms.id", "bookings.id", "booking_rooms.room_type_id", "booking_rooms.room_number",
        "bookings.status", guest_column, primary_guest_column, "bookings.check_in", "bookings.check_out", "bookings.group_booking_id",
        group_reference_column, group_name_column, "bookings.group_position"
      ]

      BookingRoom.joins(:booking)
        .left_joins(booking: :group_booking)
        .where(bookings: { hotel_id: hotel.id, status: visible_booking_statuses })
        .where.not(room_number: [ nil, "" ])
        .where("bookings.check_in < ? AND bookings.check_out > ?", date_window.window_end_at, date_window.window_start_at)
        .pluck(*columns)
        .map do |booking_room_id, booking_id, room_type_id, room_number, status, guest_name, primary_guest_name, check_in, check_out,
                 group_booking_id, group_reservation_number, group_name, group_position|
          BookingRecord.new(
            booking_room_id: booking_room_id,
            booking_id: booking_id,
            room_type_id: room_type_id,
            room_number: room_number.to_s.freeze,
            status: status.to_sym,
            guest_name: guest_name&.to_s&.freeze,
            primary_guest_name: primary_guest_name&.to_s&.freeze,
            check_in: check_in.in_time_zone(date_window.time_zone_name).to_date,
            check_out: check_out.in_time_zone(date_window.time_zone_name).to_date,
            group_booking_id:,
            group_reference: group_reference(group_reservation_number),
            group_name:,
            group_position:
          )
        end
    end

    def primary_guest_name_column
      primary_guest = BookingGuest.joins(:guest)
        .where("booking_guests.booking_id = bookings.id", role: "primary")
        .select("COALESCE(booking_guests.name_snapshot, guests.name)")
        .limit(1)
      Arel.sql("COALESCE((#{primary_guest.to_sql}), bookings.guest_name)")
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

    def group_reference(reservation_number)
      DocumentIdentifiers::HotelReferences.format(hotel:, number: reservation_number, type_code: 1)
    end

    def visible_booking_statuses
      Booking::OCCUPYING_STATUSES
    end

    def load_room_statuses
      hotel.room_statuses.pluck(:room_type_id, :room_number, :status, :priority, :dnd, :dnd_date).map do |values|
        RoomStatusRecord.new(
          room_type_id: values[0], room_number: values[1].to_s.freeze, status: values[2].to_sym,
          priority: values[3], dnd: values[4], dnd_date: values[5]
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
          assigned_to_name: metadata["assigned_to_name"]
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
  end
end
