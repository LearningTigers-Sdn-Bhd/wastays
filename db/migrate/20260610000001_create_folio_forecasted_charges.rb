class CreateFolioForecastedCharges < ActiveRecord::Migration[8.0]
  def change
    create_table :folio_forecasted_charges do |t|
      t.references :booking_folio, null: false, foreign_key: true
      t.date :stay_date, null: false
      t.string :charge_kind, null: false
      t.string :identity, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :description, null: false
      t.string :status, null: false, default: "forecast"
      t.jsonb :metadata, null: false, default: {}
      t.references :actualizing_transaction, foreign_key: { to_table: :folio_transactions }

      t.timestamps
    end

    add_index :folio_forecasted_charges, [ :booking_folio_id, :stay_date ]
    add_index :folio_forecasted_charges, [ :booking_folio_id, :status ]
    add_index :folio_forecasted_charges, [ :booking_folio_id, :charge_kind, :identity, :stay_date ],
      unique: true,
      where: "status = 'forecast'",
      name: "idx_forecasted_charges_on_unique_forecast"
  end
end
