class AddUniqueRefundIndexToFolioTransactions < ActiveRecord::Migration[8.0]
  def change
    add_index :folio_transactions,
      "booking_folio_id, ((metadata ->> 'refund_request_id'))",
      unique: true,
      where: "metadata ? 'refund_request_id'",
      name: "index_folio_transactions_on_refund_request"
  end
end
