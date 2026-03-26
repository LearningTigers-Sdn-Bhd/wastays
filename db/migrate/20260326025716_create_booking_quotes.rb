class CreateBookingQuotes < ActiveRecord::Migration[8.0]
  def change
    create_table :booking_quotes do |t|
      t.references :hotel, null: false, foreign_key: true
      t.date :check_in, null: false
      t.date :check_out, null: false
      t.integer :adults, null: false
      t.integer :children, default: 0
      t.decimal :total_amount, precision: 10, scale: 2, null: false
      t.string :currency, default: "MYR", null: false
      t.string :status, default: "pending", null: false
      t.datetime :expires_at, null: false
      t.string :token, null: false
      t.jsonb :hotel_snapshot, default: {}, null: false
      t.text :cancellation_policy_snapshot

      t.timestamps
    end
    add_index :booking_quotes, :token, unique: true
  end
end
