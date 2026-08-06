class CreateRatePlanAgeBands < ActiveRecord::Migration[8.0]
  def change
    create_table :rate_plan_age_bands do |t|
      t.references :rate_plan, null: false, foreign_key: true
      t.integer :min_age, null: false
      t.integer :max_age, null: false
      t.decimal :price_multiplier, precision: 5, scale: 2, null: false, default: 1.0
      t.string :label
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :rate_plan_age_bands, [ :rate_plan_id, :position ]
  end
end
