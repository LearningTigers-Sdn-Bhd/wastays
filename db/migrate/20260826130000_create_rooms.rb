# frozen_string_literal: true

class CreateRooms < ActiveRecord::Migration[8.0]
  def change
    create_table :rooms do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :room_type, null: false, foreign_key: true
      t.references :room_group, null: true, foreign_key: true
      t.string :number, null: false
      t.integer :position, null: false, default: 0
      t.datetime :archived_at

      t.timestamps
    end

    add_index :rooms, [ :hotel_id, :number ], unique: true
    add_index :rooms, [ :hotel_id, :archived_at ]
    add_index :rooms, [ :room_type_id, :archived_at, :position ]
    add_check_constraint :rooms,
                         "number = btrim(number) AND number <> ''",
                         name: "rooms_number_normalized"
  end
end
