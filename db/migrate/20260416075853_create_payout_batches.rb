class CreatePayoutBatches < ActiveRecord::Migration[8.0]
  def change
    create_table :payout_batches do |t|
      t.references :hotel, null: false, foreign_key: true
      t.decimal :amount
      t.string :status
      t.date :period_start
      t.date :period_end
      t.datetime :payout_at
      t.string :payout_reference
      t.jsonb :metadata

      t.timestamps
    end
  end
end
