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
        room_blocks: load_room_blocks
      )
    end

    private

    attr_reader :hotel, :date_window, :capabilities

    def load_room_types
      hotel.room_types.order(:name, :id).pluck(:id, :name, :room_numbers, :smoking_allowed, :pets_allowed).map do |values|
        RoomTypeRecord.new(**%i[id name room_numbers smoking_allowed pets_allowed].zip(values).to_h)
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
  end
end
