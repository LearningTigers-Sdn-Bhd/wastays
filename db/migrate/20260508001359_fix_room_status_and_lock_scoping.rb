class FixRoomStatusAndLockScoping < ActiveRecord::Migration[8.0]
  def up
    # Clear ephemeral data that would lack room_type_id
    execute "DELETE FROM room_locks"

    add_reference :room_locks, :room_type, null: false, foreign_key: true

    remove_index :room_locks, name: "index_room_locks_on_hotel_id_and_room_number"
    add_index :room_locks, [ :hotel_id, :room_type_id, :room_number ], unique: true, name: "idx_room_locks_on_hotel_room_type_number"

    remove_index :room_statuses, name: "index_room_statuses_on_hotel_id_and_room_number"
    add_index :room_statuses, [ :hotel_id, :room_type_id, :room_number ], unique: true, name: "idx_room_statuses_on_hotel_room_type_number"
  end

  def down
    remove_index :room_statuses, name: "idx_room_statuses_on_hotel_room_type_number"
    add_index :room_statuses, [ :hotel_id, :room_number ], unique: true, name: "index_room_statuses_on_hotel_id_and_room_number"

    remove_index :room_locks, name: "idx_room_locks_on_hotel_room_type_number"
    add_index :room_locks, [ :hotel_id, :room_number ], unique: true, name: "index_room_locks_on_hotel_id_and_room_number"

    remove_reference :room_locks, :room_type
  end
end
