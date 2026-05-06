# frozen_string_literal: true

class CreateRoomStatuses < ActiveRecord::Migration[8.0]
  def change
    create_table :room_statuses do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :room_type, null: false, foreign_key: true
      t.string :room_number, null: false
      t.string :status, null: false, default: "ready"
      t.references :last_changed_by, foreign_key: { to_table: :users }
      t.datetime :last_changed_at
      t.text :notes

      t.timestamps
    end

    add_index :room_statuses, [ :hotel_id, :room_number ], unique: true
    add_index :room_statuses, [ :hotel_id, :status ]
  end
end
