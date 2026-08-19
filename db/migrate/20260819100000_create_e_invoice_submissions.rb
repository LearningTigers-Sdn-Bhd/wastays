# frozen_string_literal: true

# Consolidates four migrations from the original feat/e-invoice branch
# (create + harden indexes + add tracking columns + replace unique index).
# None of them were ever applied on main, so the intermediate index churn is
# collapsed into the final state here. Note the original sequence ended up
# creating the same unique index twice under two names; only one is kept.
class CreateEInvoiceSubmissions < ActiveRecord::Migration[8.1]
  def change
    create_table :e_invoice_submissions do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :payout_batch, null: true, foreign_key: true

      t.string :document_scenario, null: false, default: "guest_invoice"
      t.string :document_type, null: false, default: "01" # "01" = Invoice
      t.string :submission_mode, null: false, default: "taxpayer"
      t.string :fund_collector, null: false, default: "wastays"

      t.string :supplier_name
      t.string :supplier_tin
      t.string :represented_taxpayer_tin

      t.string :internal_id          # our formatted invoice number
      t.string :uuid                 # LHDN UUID returned on submission
      t.string :long_id              # LHDN long ID for QR code
      t.string :submission_uid       # LHDN batch submission UID

      t.string :status, null: false, default: "pending"
      t.datetime :submitted_at
      t.datetime :validated_at
      t.datetime :cancelled_at

      t.boolean :requested_by_guest, null: false, default: false
      t.datetime :requested_at
      t.boolean :consolidated, null: false, default: false
      t.uuid :consolidation_batch_id
      t.datetime :payment_concluded_at
      t.string :original_invoice_internal_id

      t.jsonb :raw_response, default: {}
      t.jsonb :error_details, default: {}

      t.timestamps
    end

    add_index :e_invoice_submissions, :uuid, unique: true, where: "uuid IS NOT NULL"
    add_index :e_invoice_submissions, :status
    add_index :e_invoice_submissions, :fund_collector
    add_index :e_invoice_submissions, :consolidation_batch_id,
              name: "index_e_invoice_submissions_on_consolidation_batch_id"
    add_index :e_invoice_submissions, [ :status, :consolidated, :payment_concluded_at ],
              name: "index_e_invoice_submissions_on_status_consolidated_payment"
    add_index :e_invoice_submissions, [ :booking_id, :document_scenario, :document_type ],
              unique: true,
              where: "status <> 'cancelled'",
              name: "index_e_invoice_submissions_on_booking_scenario_type"
  end
end
