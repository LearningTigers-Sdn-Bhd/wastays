# frozen_string_literal: true

# Operational records point at a room by its number, which is a label rather
# than an identity. These nullable references give each record the stable
# identity of a physical room. The number stays for the historical record.
class AddRoomReferences < ActiveRecord::Migration[8.0]
  TABLES = %i[
    booking_rooms
    room_statuses
    room_blocks
    room_locks
    room_operational_audit_logs
    housekeeping_requests
  ].freeze

  def change
    TABLES.each do |table|
      add_reference table, :room, null: true, index: true, foreign_key: { on_delete: :nullify }
    end
  end
end
