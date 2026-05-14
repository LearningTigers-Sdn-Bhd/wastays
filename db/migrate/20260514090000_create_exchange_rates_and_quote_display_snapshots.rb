class CreateExchangeRatesAndQuoteDisplaySnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :exchange_rates do |t|
      t.string :currency_code, null: false
      t.decimal :rate_to_myr, precision: 18, scale: 8, null: false
      t.datetime :effective_at, null: false
      t.boolean :active, null: false, default: true
      t.string :source, null: false, default: "manual"
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :exchange_rates, :currency_code, unique: true
    add_check_constraint :exchange_rates, "rate_to_myr > 0", name: "exchange_rates_rate_to_myr_positive"

    add_column :booking_quotes, :display_currency, :string
    add_column :booking_quotes, :display_total_amount, :decimal, precision: 10, scale: 2
    add_column :booking_quotes, :display_exchange_rate, :decimal, precision: 18, scale: 8
    add_column :booking_quotes, :display_rate_source, :string
  end
end
