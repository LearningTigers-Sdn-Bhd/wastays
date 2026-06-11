class CreatePlanFeatures < ActiveRecord::Migration[8.0]
  def change
    create_table :plan_features do |t|
      t.references :plan, null: false, foreign_key: true
      t.references :feature, null: false, foreign_key: true
      t.boolean :enabled, null: false, default: false
      t.string :level
      t.boolean :addon, null: false, default: false
      t.timestamps
    end
    add_index :plan_features, [ :plan_id, :feature_id ], unique: true
  end
end
