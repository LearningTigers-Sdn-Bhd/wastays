class CreateRatePlans < ActiveRecord::Migration[8.0]
  def change
    create_table :rate_plans do |t|
      t.string :name, null: false
      t.references :room_type, null: false, foreign_key: true
      t.string :sell_mode, null: false, default: "per_room"
      t.string :currency, null: false, default: "MYR"

      t.timestamps
    end
  end
end
