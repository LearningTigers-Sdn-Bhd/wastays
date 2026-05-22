class AddAppliedRuleTypeToRoomRates < ActiveRecord::Migration[8.0]
  def change
    add_column :room_rates, :applied_rule_type, :string
  end
end
