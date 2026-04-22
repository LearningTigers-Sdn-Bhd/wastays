class CreateHotelPricingRules < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_pricing_rules do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :rule_type, null: false
      t.string :name
      t.decimal :price, precision: 10, scale: 2, null: false
      t.date :start_date
      t.date :end_date
      t.integer :weekdays, array: true, default: [], null: false

      t.timestamps
    end

    add_index :hotel_pricing_rules, [ :hotel_id, :rule_type ], name: "index_hotel_pricing_rules_on_hotel_and_type"
    add_index :hotel_pricing_rules, [ :hotel_id, :start_date, :end_date ], name: "index_hotel_pricing_rules_on_hotel_and_dates"
  end
end
