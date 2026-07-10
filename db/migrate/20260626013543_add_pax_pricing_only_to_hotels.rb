class AddPaxPricingOnlyToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :pax_pricing_only, :boolean, default: false, null: false
  end
end
