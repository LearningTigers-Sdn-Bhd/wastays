# frozen_string_literal: true

class AddPricingModeToRatePlanAgeBands < ActiveRecord::Migration[8.0]
  def up
    rename_column :rate_plan_age_bands, :price_multiplier, :price_value
    change_column :rate_plan_age_bands, :price_value, :decimal, precision: 10, scale: 2, default: "1.0", null: false
    add_column :rate_plan_age_bands, :pricing_mode, :string, default: "multiplier", null: false
  end

  def down
    remove_column :rate_plan_age_bands, :pricing_mode
    change_column :rate_plan_age_bands, :price_value, :decimal, precision: 5, scale: 2, default: "1.0", null: false
    rename_column :rate_plan_age_bands, :price_value, :price_multiplier
  end
end
