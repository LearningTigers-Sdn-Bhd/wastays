class CreateRefundRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :refund_requests do |t|
      t.references :booking, null: false, foreign_key: true, index: { unique: true }
      t.text :reason
      t.string :bank_name, null: false
      t.string :account_holder_name, null: false
      t.string :account_number, null: false
      t.string :account_type, null: false
      t.string :status, null: false, default: "pending"
      t.text :hotel_note
      t.decimal :refund_amount, precision: 10, scale: 2, null: false

      t.timestamps
    end
  end
end
