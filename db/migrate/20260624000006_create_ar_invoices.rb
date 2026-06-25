# frozen_string_literal: true

class CreateArInvoices < ActiveRecord::Migration[8.0]
  def change
    create_table :ar_invoices do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking_folio, null: false, foreign_key: true, index: { unique: true }
      t.references :hotel_corporate_account, null: false, foreign_key: true
      t.integer :invoice_number, null: false
      t.string :status, null: false, default: "open"
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false
      t.date :issued_on, null: false
      t.date :due_on, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :ar_invoices, [ :hotel_id, :invoice_number ], unique: true
    add_index :ar_invoices, [ :hotel_id, :status, :due_on ]
    add_index :ar_invoices, [ :hotel_corporate_account_id, :status ]
    add_check_constraint :ar_invoices, "amount > 0", name: "ar_invoices_amount_positive"
    add_check_constraint :ar_invoices, "status IN ('open', 'paid', 'void')", name: "ar_invoices_status_allowed"
  end
end
