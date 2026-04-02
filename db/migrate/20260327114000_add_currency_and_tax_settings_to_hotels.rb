class AddCurrencyAndTaxSettingsToHotels < ActiveRecord::Migration[8.0]
  def change
    add_column :hotels, :default_currency, :string, default: "MYR", null: false
    add_column :hotels, :usd_conversion_rate, :decimal, precision: 10, scale: 4, default: 4.5, null: false
    add_column :hotels, :tourism_tax_enabled, :boolean, default: false, null: false
    add_column :hotels, :tourism_tax_amount, :decimal, precision: 10, scale: 2, default: 10.0, null: false
  end
end
