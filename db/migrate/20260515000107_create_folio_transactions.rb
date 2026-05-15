class CreateFolioTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :folio_transactions do |t|
      t.references :booking_folio, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :transaction_type, null: false
      t.string :category, null: false
      t.date :posting_date, null: false
      t.string :description
      t.references :user, null: false, foreign_key: true
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :folio_transactions, :transaction_type
    add_index :folio_transactions, :category
    add_index :folio_transactions, :posting_date
  end
end
