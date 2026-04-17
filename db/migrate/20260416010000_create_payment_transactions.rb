class CreatePaymentTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_transactions do |t|
      t.references :booking_quote, null: true, foreign_key: true
      t.references :booking, null: true, foreign_key: true
      t.string :gateway, null: false
      t.string :external_reference
      t.string :gateway_order_id
      t.string :signature
      t.string :status, null: false, default: "pending"
      t.string :payment_method
      t.integer :amount_subunits
      t.string :currency
      t.string :event_source
      t.datetime :verified_at
      t.datetime :captured_at
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}
      t.jsonb :gateway_payload, null: false, default: {}

      t.timestamps
    end

    add_index :payment_transactions, [ :gateway, :external_reference ], unique: true,
      where: "external_reference IS NOT NULL",
      name: "idx_payment_transactions_on_gateway_and_external_reference"
    add_index :payment_transactions, [ :gateway, :gateway_order_id ], unique: true,
      where: "gateway_order_id IS NOT NULL",
      name: "idx_payment_transactions_on_gateway_and_order_id"
    add_index :payment_transactions, :status
  end
end
