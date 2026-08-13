# frozen_string_literal: true

class AddChannexFlatChildFeesToRatePlans < ActiveRecord::Migration[8.0]
  def change
    add_column :rate_plans, :channex_children_fee, :decimal, precision: 10, scale: 2
    add_column :rate_plans, :channex_infant_fee, :decimal, precision: 10, scale: 2
  end
end
