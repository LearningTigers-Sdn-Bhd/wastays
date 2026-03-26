class ForceAllowNullOnMarginRules < ActiveRecord::Migration[8.0]
  def change
    change_column_null :margin_rules, :settable_type, true
    change_column_null :margin_rules, :settable_id, true
    change_column_null :payment_settings, :settable_type, true
    change_column_null :payment_settings, :settable_id, true
  end
end
