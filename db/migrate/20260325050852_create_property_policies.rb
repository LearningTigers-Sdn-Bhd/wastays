class CreatePropertyPolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :property_policies do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :check_in_time
      t.string :check_out_time
      t.text :cancellation_policy

      t.timestamps
    end
  end
end
