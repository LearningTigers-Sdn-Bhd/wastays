class AllowNullSettableOnMarginRules < ActiveRecord::Migration[8.0]
  def up
    change_column :margin_rules, :settable_type, :string, null: true
    change_column :margin_rules, :settable_id, :bigint, null: true
    change_column :payment_settings, :settable_type, :string, null: true
    change_column :payment_settings, :settable_id, :bigint, null: true
  end

  def down
    change_column :margin_rules, :settable_type, :string, null: false
    change_column :margin_rules, :settable_id, :bigint, null: false
    change_column :payment_settings, :settable_type, :string, null: false
    change_column :payment_settings, :settable_id, :bigint, null: false
  end
end
