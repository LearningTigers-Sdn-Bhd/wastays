# frozen_string_literal: true

class AddArInvoiceCorrections < ActiveRecord::Migration[8.1]
  def change
    remove_index :invoices, :booking_folio_id
    add_index :invoices, :booking_folio_id, unique: true, where: "state <> 'voided'", name: "idx_invoices_current_folio"
    remove_index :ar_invoices, :booking_folio_id
    add_index :ar_invoices, :booking_folio_id, unique: true, where: "status <> 'void'", name: "idx_ar_invoices_current_folio"

    create_table :ar_invoice_corrections do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking_folio, null: false, foreign_key: true
      t.references :original_receivable, null: false, foreign_key: { to_table: :ar_invoices }
      t.references :replacement_receivable, foreign_key: { to_table: :ar_invoices }
      t.references :opened_by, null: false, foreign_key: { to_table: :users }
      t.references :closed_by, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "editing"
      t.text :reason, null: false
      t.string :credit_reference
      t.jsonb :original_snapshot, null: false, default: {}
      t.jsonb :corrected_snapshot, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.boolean :send_documents, null: false, default: false
      t.datetime :completed_at
      t.text :error_message
      t.timestamps
    end
    add_index :ar_invoice_corrections, :booking_folio_id, unique: true,
      where: "status IN ('editing', 'processing', 'failed')", name: "idx_ar_corrections_unresolved_folio"
    add_index :ar_invoice_corrections, [ :hotel_id, :credit_reference ], unique: true
    add_check_constraint :ar_invoice_corrections,
      "status IN ('editing', 'processing', 'failed', 'completed', 'unchanged')", name: "ar_correction_status_allowed"

    add_reference :e_invoice_submissions, :invoice, foreign_key: true
    add_reference :e_invoice_submissions, :ar_invoice_correction, foreign_key: true
    add_column :e_invoice_submissions, :document_payload, :jsonb, null: false, default: {}
    remove_index :e_invoice_submissions, name: "index_e_invoice_submissions_on_booking_scenario_type"
    add_index :e_invoice_submissions, [ :booking_id, :document_scenario, :document_type ], unique: true,
      where: "status <> 'cancelled' AND ar_invoice_correction_id IS NULL",
      name: "index_e_invoice_submissions_on_booking_scenario_type"
    add_index :e_invoice_submissions, [ :ar_invoice_correction_id, :document_type ], unique: true,
      where: "ar_invoice_correction_id IS NOT NULL", name: "idx_e_invoice_correction_type"
    reversible do |direction|
      direction.down do
        if select_value("SELECT EXISTS (SELECT 1 FROM ar_invoice_corrections)")
          raise ActiveRecord::IrreversibleMigration, "Correction history must be preserved. Roll forward instead."
        end
      end
    end
  end
end
