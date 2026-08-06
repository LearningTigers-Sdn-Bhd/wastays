# frozen_string_literal: true

class CreateFolioInvoicesAndRevisions < ActiveRecord::Migration[8.0]
  def up
    create_table :folio_invoices do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking_folio, null: false, foreign_key: true, index: { unique: true }
      t.references :issued_by, foreign_key: { to_table: :users }
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

    backfill_existing_invoices!
  end

  def down
    drop_table :folio_invoice_revisions
    drop_table :folio_invoices
  end

  private

  def backfill_existing_invoices!
    execute <<~SQL.squish
      INSERT INTO folio_invoices (
        hotel_id, booking_folio_id, issued_by_id,
        invoice_number, invoice_year, invoice_reference,
        state, current_revision_number, issued_at, legacy, metadata,
        created_at, updated_at
      )
      SELECT
        booking_folios.hotel_id,
        booking_folios.id,
        booking_folios.closed_by_id,
        booking_folios.invoice_number,
        booking_folios.invoice_year,
        booking_folios.invoice_reference,
        CASE booking_folios.status
          WHEN 'open' THEN 'under_correction'
          WHEN 'voided' THEN 'voided'
          ELSE 'finalized'
        END,
        1,
        COALESCE(booking_folios.closed_at, booking_folios.updated_at),
        TRUE,
        jsonb_build_object('legacy_generated', TRUE),
        booking_folios.created_at,
        booking_folios.updated_at
      FROM booking_folios
      WHERE booking_folios.invoice_number IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM ar_invoices WHERE ar_invoices.booking_folio_id = booking_folios.id
        )
    SQL

    execute <<~SQL.squish
      INSERT INTO folio_invoice_revisions (
        hotel_id, folio_invoice_id, issued_by_id, revision_number,
        document_reference, snapshot, issued_at, created_at, updated_at
      )
      SELECT
        folio_invoices.hotel_id,
        folio_invoices.id,
        folio_invoices.issued_by_id,
        1,
        folio_invoices.invoice_reference,
        jsonb_build_object('legacy_generated', TRUE),
        folio_invoices.issued_at,
        folio_invoices.created_at,
        folio_invoices.updated_at
      FROM folio_invoices
      WHERE folio_invoices.legacy = TRUE
    SQL
  end
end
