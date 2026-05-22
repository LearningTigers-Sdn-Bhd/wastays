class AddMultiRangesToHotelPricingRules < ActiveRecord::Migration[8.0]
  def change
    add_column :hotel_pricing_rules, :metadata, :jsonb
  end
end
