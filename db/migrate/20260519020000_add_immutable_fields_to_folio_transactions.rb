# frozen_string_literal: true

class AddImmutableFieldsToFolioTransactions < ActiveRecord::Migration[8.0]
  def change
    change_table :folio_transactions, bulk: true do |t|
      t.references :reversal_of_transaction, foreign_key: { to_table: :folio_transactions }, index: true
      t.references :voided_by_transaction, foreign_key: { to_table: :folio_transactions }, index: true
      t.string :correction_reason
      t.text :correction_note
      t.datetime :posted_at
      t.string :currency
    end

    add_index :folio_transactions, [ :booking_folio_id, :posting_date ], name: "index_folio_transactions_on_folio_and_posting_date"
  end
end
