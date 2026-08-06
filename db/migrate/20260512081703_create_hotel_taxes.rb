class CreateHotelTaxes < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_taxes do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :name, null: false
      t.string :rate_type, null: false, default: "flat"  # "flat" | "percentage"
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.boolean :enabled, default: true, null: false
      t.boolean :foreign_guests_only, default: false, null: false
      t.timestamps
    end
  end
end
