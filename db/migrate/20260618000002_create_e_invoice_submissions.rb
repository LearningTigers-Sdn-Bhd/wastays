class CreateEInvoiceSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :e_invoice_submissions do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :payout_batch, null: true, foreign_key: true
      t.string :document_scenario, null: false, default: "guest_invoice"
      t.string :document_type, default: "01", null: false  # "01" = Invoice
      t.string :submission_mode, null: false, default: "taxpayer"
      t.string :fund_collector, null: false, default: "wastays"
      t.string :supplier_name
      t.string :supplier_tin
      t.string :represented_taxpayer_tin
      t.string :internal_id                 # Our formatted invoice number
      t.string :uuid                        # LHDN UUID returned on submission
      t.string :long_id                     # LHDN long ID for QR code
      t.string :submission_uid             # LHDN batch submission UID
      t.string :status, default: "pending", null: false
      t.datetime :submitted_at
      t.datetime :validated_at
      t.datetime :cancelled_at
      t.jsonb :raw_response, default: {}
      t.jsonb :error_details, default: {}
      t.timestamps
    end
    add_index :e_invoice_submissions, [ :booking_id, :document_scenario ], name: "index_e_invoice_submissions_on_booking_and_scenario"
    add_index :e_invoice_submissions, :uuid, unique: true, where: "uuid IS NOT NULL"
    add_index :e_invoice_submissions, :status
  end
end
