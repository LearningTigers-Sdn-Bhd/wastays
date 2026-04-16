class CreateSetupFeeRules < ActiveRecord::Migration[8.0]
  def change
    create_table :setup_fee_rules do |t|
      t.references :settable, polymorphic: true, index: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, default: "MYR", null: false
      t.string :status, null: false

      t.timestamps
    end

    add_index :setup_fee_rules, [ :settable_type, :settable_id ], name: "index_setup_fee_rules_on_settable"
    add_index :setup_fee_rules, :status, unique: true, where: "status = 'active' AND settable_type IS NULL AND settable_id IS NULL", name: "index_setup_fee_rules_on_active_global_default"
    add_index :setup_fee_rules, [ :settable_type, :settable_id ], unique: true, where: "status = 'active' AND settable_type = 'Hotel'", name: "index_setup_fee_rules_on_active_hotel_overrides"
  end
end
