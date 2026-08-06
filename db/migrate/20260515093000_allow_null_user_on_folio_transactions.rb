class AllowNullUserOnFolioTransactions < ActiveRecord::Migration[8.0]
  def change
    change_column_null :folio_transactions, :user_id, true
  end
end
