class AddPerGuestOccupancyPrices < ActiveRecord::Migration[8.0]
  def change
    create_table :room_type_rate_plan_occupancy_prices do |t|
      t.references :room_type_rate_plan, null: false, foreign_key: true, index: false
      t.integer :adults, null: false
      t.decimal :price, precision: 10, scale: 2, null: false
      t.timestamps
    end

    add_index :room_type_rate_plan_occupancy_prices,
      [ :room_type_rate_plan_id, :adults ],
      unique: true,
      name: "idx_rtrp_occupancy_prices_unique"

    add_column :room_rates, :occupancy_prices, :jsonb, null: false, default: {}
  end
end
