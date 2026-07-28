# frozen_string_literal: true

# Release 2 of dropping the duplicate folio invoice tables. Everything these
# tables held was copied into invoices/invoice_revisions by ExpandUnifiedInvoices,
# and EnforceUnifiedDualInvoiceTypes already re-points the "a folio never holds
# both document types" guarantee onto invoices.
#
# Run only once Release 1 is fully rolled out and the parity checks in
# DOCUMENTS_INVOICING_PLAN.md return zero rows.
class DropFolioInvoices < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      DROP TRIGGER IF EXISTS ar_invoices_prevent_dual_invoice_types ON ar_invoices;
      DROP TRIGGER IF EXISTS folio_invoices_prevent_dual_invoice_types ON folio_invoices;
      DROP FUNCTION IF EXISTS prevent_dual_folio_invoice_types();

      DROP TRIGGER IF EXISTS folio_invoice_revisions_immutable ON folio_invoice_revisions;
      DROP FUNCTION IF EXISTS prevent_folio_invoice_revision_mutation();
    SQL

    drop_table :folio_invoice_revisions
    drop_table :folio_invoices
  end

  # Not a true reverse: this restores the empty tables and their constraints so
  # the schema can roll back, but the rows are gone. Recover them by re-running
  # CreateFolioInvoicesAndRevisions' backfill against booking_folios, or from a
  # database snapshot.
  def down
    create_table :folio_invoices do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking_folio, null: false, foreign_key: true, index: { unique: true }
      t.references :issued_by, foreign_key: { to_table: :users }
      t.references :invoice, foreign_key: true, index: { unique: true }
      t.integer :invoice_number, null: false
      t.integer :invoice_year, null: false
      t.string :invoice_reference, null: false
      t.string :state, null: false, default: "finalized"
      t.integer :current_revision_number, null: false, default: 1
      t.datetime :issued_at, null: false
      t.boolean :legacy, null: false, default: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :folio_invoices, [ :hotel_id, :invoice_year, :invoice_number ],
      unique: true, name: :idx_folio_invoices_year_number
    add_index :folio_invoices, [ :hotel_id, :invoice_reference ],
      unique: true, name: :idx_folio_invoices_reference
    add_check_constraint :folio_invoices,
      "state IN ('finalized', 'under_correction', 'voided')",
      name: :folio_invoices_state_allowed
    add_check_constraint :folio_invoices,
      "current_revision_number > 0",
      name: :folio_invoices_current_revision_positive

    create_table :folio_invoice_revisions do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :folio_invoice, null: false, foreign_key: true
      t.references :issued_by, foreign_key: { to_table: :users }
      t.integer :revision_number, null: false
      t.string :document_reference, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.datetime :issued_at, null: false
      t.timestamps
    end

    add_index :folio_invoice_revisions, [ :folio_invoice_id, :revision_number ],
      unique: true, name: :idx_folio_invoice_revisions_number
    add_index :folio_invoice_revisions, [ :hotel_id, :document_reference ],
      unique: true, name: :idx_folio_invoice_revisions_reference
    add_check_constraint :folio_invoice_revisions,
      "revision_number > 0",
      name: :folio_invoice_revisions_number_positive
  end
end
