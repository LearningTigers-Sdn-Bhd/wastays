class CreateJournalBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :journal_batches do |t|
      t.references :hotel, null: false, foreign_key: true
      t.date :business_date, null: false
      t.string :status, default: "finalized", null: false
      t.datetime :finalized_at
      t.jsonb :summary_data, default: {}, null: false

      t.timestamps
    end

    add_index :journal_batches, [ :hotel_id, :business_date ], unique: true

    create_table :journal_batch_entries do |t|
      t.references :journal_batch, null: false, foreign_key: true
      t.string :gl_code, null: false
      t.string :transaction_type, null: false
      t.decimal :debit_amount, precision: 10, scale: 2, default: 0, null: false
      t.decimal :credit_amount, precision: 10, scale: 2, default: 0, null: false
      t.string :description

      t.timestamps
    end
  end
end
