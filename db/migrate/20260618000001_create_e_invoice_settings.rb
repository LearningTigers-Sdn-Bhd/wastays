class CreateEInvoiceSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :e_invoice_settings do |t|
      t.references :hotel, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, default: false, null: false

      # Hotel as BUYER — used in Phase 2 (payout & commission invoices where hotel is buyer)
      t.string :hotel_tin   # Hotel's LHDN TIN
      t.string :hotel_brn   # Hotel's SSM Business Registration Number

      t.timestamps
    end
  end
end
