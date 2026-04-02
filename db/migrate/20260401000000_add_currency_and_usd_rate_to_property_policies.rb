class AddCurrencyAndUsdRateToPropertyPolicies < ActiveRecord::Migration[8.0]
  def change
    add_column :property_policies, :currency, :string, null: false, default: "MYR"
    add_column :property_policies, :usd_rate, :decimal, precision: 10, scale: 4, null: false, default: 0.21
  end
end
