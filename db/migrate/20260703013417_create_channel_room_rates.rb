class CreateChannelRoomRates < ActiveRecord::Migration[8.0]
  def change
    create_table :channel_room_rates do |t|
      t.references :room_type, null: false, foreign_key: true
      t.references :rate_plan, null: true, foreign_key: true
      t.string :channel_id, null: false
      t.string :channel_rate_plan_id
      t.date :date, null: false
      t.decimal :price, precision: 10, scale: 2
      t.integer :min_stay
      t.integer :max_stay
      t.boolean :closed_to_arrival
      t.boolean :closed_to_departure
      t.boolean :stop_sell
      t.integer :availability
      t.string :currency, default: "MYR", null: false

      t.timestamps
    end

    add_index :channel_room_rates, [ :room_type_id, :rate_plan_id, :channel_rate_plan_id, :date, :currency ], unique: true, name: 'idx_channel_room_rates_uniqueness'
  end
end
