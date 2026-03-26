class CreateBookings < ActiveRecord::Migration[8.0]
  def change
    create_table :bookings do |t|
      t.references :booking_quote, foreign_key: true
      t.references :hotel, null: false, foreign_key: true
      t.string :guest_name, null: false
      t.string :guest_email, null: false
      t.string :guest_phone, null: false
      t.decimal :total_amount, precision: 10, scale: 2, null: false
      t.string :currency, default: "MYR", null: false
      t.string :status, default: "pending", null: false
      t.string :payment_status, default: "pending", null: false
      t.string :confirmation_token, null: false
      t.date :check_in, null: false
      t.date :check_out, null: false
      t.integer :adults, null: false
      t.integer :children, default: 0
      t.jsonb :hotel_snapshot, default: {}, null: false
      t.text :cancellation_policy_snapshot

      t.timestamps
    end
    add_index :bookings, :confirmation_token, unique: true
    add_index :bookings, :status
    add_index :bookings, :payment_status
  end
end
