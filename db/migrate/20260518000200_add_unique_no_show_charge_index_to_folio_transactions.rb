class AddUniqueNoShowChargeIndexToFolioTransactions < ActiveRecord::Migration[8.0]
  def change
    add_index :folio_transactions,
      "booking_folio_id, ((metadata ->> 'no_show_charge_key'))",
      unique: true,
      where: "metadata ? 'no_show_charge_key'",
      name: "index_folio_transactions_on_no_show_charge"
  end
end
