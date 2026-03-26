class CreateBookingRooms < ActiveRecord::Migration[8.0]
  def change
    create_table :booking_rooms do |t|
      t.references :booking, null: false, foreign_key: true
      t.references :room_type, null: false, foreign_key: true
      t.integer :quantity, default: 1, null: false
      t.decimal :subtotal, precision: 10, scale: 2, null: false
      t.jsonb :room_type_snapshot, default: {}, null: false
      t.jsonb :nightly_rate_snapshot, default: {}, null: false
      t.jsonb :occupancy_snapshot, default: {}, null: false

      t.timestamps
    end
  end
end
