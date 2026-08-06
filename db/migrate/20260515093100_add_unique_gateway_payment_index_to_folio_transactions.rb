class AddUniqueGatewayPaymentIndexToFolioTransactions < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_folio_transactions_on_gateway_payment
      ON folio_transactions (booking_folio_id, ((metadata->>'payment_transaction_id')))
      WHERE metadata ? 'payment_transaction_id'
    SQL
  end

  def down
    execute <<~SQL.squish
      DROP INDEX index_folio_transactions_on_gateway_payment
    SQL
  end
end
