# frozen_string_literal: true

# Long-stay discounts on a rate plan: "stay at least N nights, get X off".
# The longest rule a stay qualifies for wins, and it discounts either every
# night of the stay or only the nights from a given night onward. Direct
# channels only -- nothing here is sent to the channel manager.
class CreateRatePlanStayDiscounts < ActiveRecord::Migration[8.1]
  def change
    create_table :rate_plan_stay_discounts do |t|
      t.references :rate_plan, null: false, foreign_key: true, index: false
      t.integer :min_nights, null: false
      t.string :discount_type, null: false, default: "percent"
      t.decimal :value, precision: 10, scale: 2, null: false
      t.integer :from_night, null: false, default: 1
      t.timestamps
    end

    add_index :rate_plan_stay_discounts, %i[rate_plan_id min_nights], unique: true, name: "idx_rate_plan_stay_discounts_unique"
    add_check_constraint :rate_plan_stay_discounts, "min_nights >= 2", name: "rate_plan_stay_discounts_min_nights_check"
    add_check_constraint :rate_plan_stay_discounts, "discount_type IN ('percent', 'amount')", name: "rate_plan_stay_discounts_type_check"
    add_check_constraint :rate_plan_stay_discounts, "value > 0 AND (discount_type <> 'percent' OR value <= 100)", name: "rate_plan_stay_discounts_value_check"
    add_check_constraint :rate_plan_stay_discounts, "from_night >= 1 AND from_night <= min_nights", name: "rate_plan_stay_discounts_from_night_check"
  end
end
