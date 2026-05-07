class CreateRoomLocks < ActiveRecord::Migration[8.0]
  def change
    create_table :room_locks do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :room_number, null: false
      t.datetime :expires_at, null: false, index: true

      t.timestamps
    end

    add_index :room_locks, [ :hotel_id, :room_number ], unique: true
  end
end
