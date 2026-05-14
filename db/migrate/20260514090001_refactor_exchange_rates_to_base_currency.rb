class RefactorExchangeRatesToBaseCurrency < ActiveRecord::Migration[8.0]
  def up
    # 1. Add base_currency column
    add_column :exchange_rates, :base_currency, :string, default: "MYR", null: false

    # 2. Rename rate_to_myr to rate
    rename_column :exchange_rates, :rate_to_myr, :rate

    # 3. Update the index to include base_currency
    remove_index :exchange_rates, :currency_code
    add_index :exchange_rates, [ :base_currency, :currency_code ], unique: true

    # 4. Remove the check constraint and add a new one
    execute "ALTER TABLE exchange_rates DROP CONSTRAINT exchange_rates_rate_to_myr_positive"
    add_check_constraint :exchange_rates, "rate > 0", name: "exchange_rates_rate_positive"
  end

  def down
    remove_check_constraint :exchange_rates, name: "exchange_rates_rate_positive"
    execute "ALTER TABLE exchange_rates ADD CONSTRAINT exchange_rates_rate_to_myr_positive CHECK (rate > 0)"

    remove_index :exchange_rates, [ :base_currency, :currency_code ]
    add_index :exchange_rates, :currency_code, unique: true

    rename_column :exchange_rates, :rate, :rate_to_myr
    remove_column :exchange_rates, :base_currency
  end
end
