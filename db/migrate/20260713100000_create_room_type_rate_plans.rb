class CreateRoomTypeRatePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :room_type_rate_plans do |t|
      t.references :room_type, null: false, foreign_key: true
      t.references :rate_plan, null: false, foreign_key: true
      t.string :pricing_mode, default: "fixed", null: false
      t.decimal :pricing_value, precision: 10, scale: 2

      t.timestamps
    end
  end
end
