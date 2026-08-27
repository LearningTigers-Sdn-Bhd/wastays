# frozen_string_literal: true

# Match each operational record to its physical room by hotel and number.
#
# A record whose number no longer exists in the hotel keeps a null reference.
# That is the correct outcome: the room is gone, and the stored number remains
# the only true statement about where the record happened.
class BackfillRoomReferences < ActiveRecord::Migration[8.0]
  # booking_rooms reaches its hotel through the booking. The rest carry
  # hotel_id themselves.
  TABLES = {
    "booking_rooms" => "SELECT bookings.hotel_id FROM bookings WHERE bookings.id = booking_rooms.booking_id",
    "room_statuses" => nil,
    "room_blocks" => nil,
    "room_locks" => nil,
    "room_operational_audit_logs" => nil,
    "housekeeping_requests" => nil
  }.freeze

  def up
    TABLES.each do |table, hotel_source|
      hotel_expression = hotel_source ? "(#{hotel_source})" : "#{table}.hotel_id"

      execute(<<~SQL.squish)
        UPDATE #{table}
        SET room_id = rooms.id
        FROM rooms
        WHERE #{table}.room_id IS NULL
          AND #{table}.room_number IS NOT NULL
          AND btrim(#{table}.room_number) <> ''
          AND rooms.number = btrim(#{table}.room_number)
          AND rooms.hotel_id = #{hotel_expression}
      SQL
    end
  end

  def down
    TABLES.each_key { |table| execute("UPDATE #{table} SET room_id = NULL") }
  end
end
