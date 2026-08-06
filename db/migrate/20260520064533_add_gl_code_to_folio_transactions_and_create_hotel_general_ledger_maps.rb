class AddGlCodeToFolioTransactionsAndCreateHotelGeneralLedgerMaps < ActiveRecord::Migration[8.0]
  def change
    add_column :folio_transactions, :gl_code, :string
    add_index :folio_transactions, :gl_code

    create_table :hotel_general_ledger_maps do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :transaction_category, null: false
      t.string :gl_code, null: false
      t.string :description

      t.timestamps
    end

    add_index :hotel_general_ledger_maps, [ :hotel_id, :transaction_category ], unique: true, name: "idx_hotel_gl_maps_on_hotel_and_category"
  end
end
