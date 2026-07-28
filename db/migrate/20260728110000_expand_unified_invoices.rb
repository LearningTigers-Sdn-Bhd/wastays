# frozen_string_literal: true

class ExpandUnifiedInvoices < ActiveRecord::Migration[8.0]
  def up
    create_table :invoices do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking_folio, null: false, foreign_key: true, index: { unique: true }
      t.references :issued_by, foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.integer :invoice_number, null: false
      t.integer :invoice_year, null: false
      t.string :invoice_reference, null: false
      t.string :state, null: false, default: "finalized"
      t.integer :current_revision_number, null: false, default: 1
      t.date :issued_on, null: false
      t.datetime :issued_at, null: false
      t.boolean :legacy, null: false, default: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :invoices, [ :hotel_id, :kind, :invoice_year, :invoice_number ],
      unique: true, name: :idx_invoices_kind_year_number
    add_index :invoices, [ :hotel_id, :invoice_reference ],
      unique: true, name: :idx_invoices_reference
    add_check_constraint :invoices,
      "kind IN ('settled', 'direct_bill')",
      name: :invoices_kind_allowed
    add_check_constraint :invoices,
      "state IN ('finalized', 'under_correction', 'voided')",
      name: :invoices_state_allowed
    add_check_constraint :invoices,
      "current_revision_number > 0",
      name: :invoices_current_revision_positive

    create_table :invoice_revisions do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :invoice, null: false, foreign_key: true
      t.references :issued_by, foreign_key: { to_table: :users }
      t.integer :revision_number, null: false
      t.string :document_reference, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.datetime :issued_at, null: false
      t.timestamps
    end

    add_index :invoice_revisions, [ :invoice_id, :revision_number ],
      unique: true, name: :idx_invoice_revisions_number
    add_index :invoice_revisions, [ :hotel_id, :document_reference ],
      unique: true, name: :idx_invoice_revisions_reference
    add_check_constraint :invoice_revisions,
      "revision_number > 0",
      name: :invoice_revisions_number_positive

    add_reference :folio_invoices, :invoice, foreign_key: true, index: { unique: true }
    add_reference :ar_invoices, :invoice, foreign_key: true, index: { unique: true }

    backfill_settled_invoices!
    backfill_direct_bill_invoices!
  end

  def down
    execute "DROP TRIGGER IF EXISTS invoice_revisions_immutable ON invoice_revisions"
    execute "DROP FUNCTION IF EXISTS prevent_invoice_revision_mutation()"
    remove_reference :ar_invoices, :invoice, foreign_key: true
    remove_reference :folio_invoices, :invoice, foreign_key: true
    drop_table :invoice_revisions
    drop_table :invoices
  end

  private

  def backfill_settled_invoices!
    execute <<~SQL.squish
      INSERT INTO invoices (
        hotel_id, booking_folio_id, issued_by_id, kind,
        invoice_number, invoice_year, invoice_reference,
        state, current_revision_number, issued_on, issued_at,
        legacy, metadata, created_at, updated_at
      )
      SELECT
        hotel_id, booking_folio_id, issued_by_id, 'settled',
        invoice_number, invoice_year, invoice_reference,
        state, current_revision_number, issued_at::date, issued_at,
        legacy, metadata, created_at, updated_at
      FROM folio_invoices
    SQL

    execute <<~SQL.squish
      UPDATE folio_invoices
      SET invoice_id = invoices.id
      FROM invoices
      WHERE invoices.booking_folio_id = folio_invoices.booking_folio_id
        AND invoices.kind = 'settled'
    SQL

    execute <<~SQL.squish
      INSERT INTO invoice_revisions (
        hotel_id, invoice_id, issued_by_id, revision_number,
        document_reference, snapshot, issued_at, created_at, updated_at
      )
      SELECT
        revisions.hotel_id, folio_invoices.invoice_id, revisions.issued_by_id,
        revisions.revision_number, revisions.document_reference,
        revisions.snapshot, revisions.issued_at, revisions.created_at, revisions.updated_at
      FROM folio_invoice_revisions revisions
      INNER JOIN folio_invoices ON folio_invoices.id = revisions.folio_invoice_id
    SQL
  end

  def backfill_direct_bill_invoices!
    execute <<~SQL.squish
      INSERT INTO invoices (
        hotel_id, booking_folio_id, kind,
        invoice_number, invoice_year, invoice_reference,
        state, current_revision_number, issued_on, issued_at,
        legacy, metadata, created_at, updated_at
      )
      SELECT
        hotel_id, booking_folio_id, 'direct_bill',
        invoice_number, invoice_year, invoice_reference,
        CASE WHEN status = 'void' THEN 'voided' ELSE 'finalized' END,
        1, issued_on, created_at,
        NOT (metadata ? 'document_snapshot'),
        metadata - 'document_snapshot', created_at, updated_at
      FROM ar_invoices
    SQL

    execute <<~SQL.squish
      UPDATE ar_invoices
      SET invoice_id = invoices.id
      FROM invoices
      WHERE invoices.booking_folio_id = ar_invoices.booking_folio_id
        AND invoices.kind = 'direct_bill'
    SQL

    execute <<~SQL.squish
      INSERT INTO invoice_revisions (
        hotel_id, invoice_id, revision_number, document_reference,
        snapshot, issued_at, created_at, updated_at
      )
      SELECT
        ar_invoices.hotel_id, ar_invoices.invoice_id, 1,
        ar_invoices.invoice_reference,
        ar_invoices.metadata->'document_snapshot',
        ar_invoices.created_at, ar_invoices.created_at, ar_invoices.updated_at
      FROM ar_invoices
      WHERE ar_invoices.metadata ? 'document_snapshot'
    SQL
  end
end
