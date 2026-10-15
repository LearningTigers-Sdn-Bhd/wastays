# frozen_string_literal: true

class AddDayUseHoursToRatePlans < ActiveRecord::Migration[8.1]
  def change
    add_column :rate_plans, :day_use_hours, :integer
    add_check_constraint :rate_plans, "day_use_hours IS NULL OR day_use_hours BETWEEN 1 AND 24",
      name: "rate_plans_day_use_hours_range"
  end
end
