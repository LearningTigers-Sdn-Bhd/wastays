# frozen_string_literal: true

# Re-points the "a folio never holds both document types" guarantee from
# folio_invoices onto invoices, ahead of dropping folio_invoices. The original
# trigger from EnforceInvoiceDocumentIntegrity stays active until that drop, so
# the invariant is never unguarded during the rollout.
#
# Only settled invoices conflict with a receivable. A direct-bill invoice and
# its ar_invoices row are the intended pairing, already validated by
# Receivable#invoice_matches_receivable.
class EnforceUnifiedDualInvoiceTypes < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION prevent_dual_invoice_types()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        PERFORM 1
        FROM booking_folios
        WHERE id = NEW.booking_folio_id
        FOR UPDATE;

        IF NOT FOUND THEN
          RAISE EXCEPTION 'booking folio % does not exist', NEW.booking_folio_id;
        END IF;

        IF TG_TABLE_NAME = 'invoices' THEN
          IF NEW.kind = 'settled' AND EXISTS (
            SELECT 1 FROM ar_invoices
            WHERE booking_folio_id = NEW.booking_folio_id
          ) THEN
            RAISE EXCEPTION 'a booking folio cannot have both an AR invoice and a settled invoice';
          END IF;
        ELSIF EXISTS (
          SELECT 1 FROM invoices
          WHERE booking_folio_id = NEW.booking_folio_id
            AND kind = 'settled'
        ) THEN
          RAISE EXCEPTION 'a booking folio cannot have both an AR invoice and a settled invoice';
        END IF;

        RETURN NEW;
      END;
      $$;

      DROP TRIGGER IF EXISTS invoices_prevent_dual_invoice_types ON invoices;
      CREATE TRIGGER invoices_prevent_dual_invoice_types
      BEFORE INSERT OR UPDATE OF booking_folio_id, kind ON invoices
      FOR EACH ROW EXECUTE FUNCTION prevent_dual_invoice_types();

      DROP TRIGGER IF EXISTS ar_invoices_prevent_dual_unified_invoice_types ON ar_invoices;
      CREATE TRIGGER ar_invoices_prevent_dual_unified_invoice_types
      BEFORE INSERT OR UPDATE OF booking_folio_id ON ar_invoices
      FOR EACH ROW EXECUTE FUNCTION prevent_dual_invoice_types();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS ar_invoices_prevent_dual_unified_invoice_types ON ar_invoices;
      DROP TRIGGER IF EXISTS invoices_prevent_dual_invoice_types ON invoices;
      DROP FUNCTION IF EXISTS prevent_dual_invoice_types();
    SQL
  end
end
