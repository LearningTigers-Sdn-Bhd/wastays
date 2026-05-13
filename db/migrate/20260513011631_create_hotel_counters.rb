class CreateHotelCounters < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_counters do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :counter_type, null: false  # "reservation" | "folio" | "receipt" | "guest_registration"
      t.integer :last_value, null: false, default: 0
      t.timestamps
    end

    add_index :hotel_counters, [ :hotel_id, :counter_type ], unique: true
  end
end
