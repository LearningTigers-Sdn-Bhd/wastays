# frozen_string_literal: true

class CreateArPayments < ActiveRecord::Migration[8.0]
  def change
    create_table :ar_payments do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :hotel_corporate_account, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false
      t.string :reference_number, null: false
      t.date :received_at, null: false
      t.string :payment_method, null: false, default: "bank_transfer"
      t.text :notes
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    create_table :ar_payment_allocations do |t|
      t.references :ar_payment, null: false, foreign_key: true
      t.references :ar_invoice, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :ar_payments, [ :hotel_id, :received_at ]
    add_index :ar_payments, [ :hotel_id, :reference_number ]
    add_index :ar_payments, [ :hotel_corporate_account_id, :received_at ], name: "idx_ar_payments_on_account_received_at"
    add_index :ar_payment_allocations, [ :ar_payment_id, :ar_invoice_id ], unique: true, name: "idx_ar_allocations_unique_payment_invoice"
    add_index :ar_payment_allocations, [ :ar_invoice_id, :created_at ], name: "idx_ar_allocations_on_invoice_created_at"
    add_check_constraint :ar_payments, "amount > 0", name: "ar_payments_amount_positive"
    add_check_constraint :ar_payment_allocations, "amount > 0", name: "ar_payment_allocations_amount_positive"
  end
end
