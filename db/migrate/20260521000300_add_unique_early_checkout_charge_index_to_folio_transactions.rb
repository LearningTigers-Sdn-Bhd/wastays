class AddUniqueEarlyCheckoutChargeIndexToFolioTransactions < ActiveRecord::Migration[8.0]
  def change
    add_index :folio_transactions,
      "booking_folio_id, ((metadata ->> 'early_checkout_charge_key'))",
      unique: true,
      where: "metadata ? 'early_checkout_charge_key'",
      name: "index_folio_transactions_on_early_checkout_charge"
  end
end
