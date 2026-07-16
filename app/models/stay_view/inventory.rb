# frozen_string_literal: true

module StayView
  RoomTypeRecord = Data.define(:id, :name, :room_numbers, :smoking_allowed, :pets_allowed) do
    def initialize(id:, name:, room_numbers:, smoking_allowed:, pets_allowed:)
      super(
        id: id,
        name: name.to_s.freeze,
        room_numbers: Immutable.array(Array(room_numbers).flatten.compact.map(&:to_s).reject(&:blank?)),
        smoking_allowed: smoking_allowed,
        pets_allowed: pets_allowed
      )
    end
  end

  BookingRecord = Data.define(:booking_room_id, :booking_id, :room_type_id, :room_number, :status, :guest_name, :check_in, :check_out)
  RoomStatusRecord = Data.define(:room_type_id, :room_number, :status, :priority, :dnd, :dnd_date)
  RoomBlockRecord = Data.define(:id, :room_type_id, :room_number, :block_type, :reason, :start_date, :end_date)

  Inventory = Data.define(:room_types, :bookings, :room_statuses, :room_blocks) do
    def initialize(room_types:, bookings:, room_statuses:, room_blocks:)
      super(
        room_types: Immutable.array(room_types),
        bookings: Immutable.array(bookings),
        room_statuses: Immutable.array(room_statuses),
        room_blocks: Immutable.array(room_blocks)
      )
    end
  end
end
