# frozen_string_literal: true

class AddSingleSupplementToPricingModels < ActiveRecord::Migration[8.0]
  def change
    add_column :rate_plans, :single_supplement, :decimal, precision: 10, scale: 2, default: 0.0, null: false
    add_column :room_rates, :single_supplement, :decimal, precision: 10, scale: 2
  end
end
