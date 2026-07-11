class AddAllowPaxPricingToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :allow_pax_pricing, :boolean, default: false, null: false
  end
end
