# frozen_string_literal: true

class EnforceInvoiceDocumentIntegrity < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE FUNCTION prevent_dual_folio_invoice_types()
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

        IF TG_TABLE_NAME = 'folio_invoices' THEN
          IF EXISTS (
            SELECT 1 FROM ar_invoices
            WHERE booking_folio_id = NEW.booking_folio_id
          ) THEN
            RAISE EXCEPTION 'a booking folio cannot have both an AR invoice and a folio invoice';
          END IF;
        ELSIF EXISTS (
          SELECT 1 FROM folio_invoices
          WHERE booking_folio_id = NEW.booking_folio_id
        ) THEN
          RAISE EXCEPTION 'a booking folio cannot have both an AR invoice and a folio invoice';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER folio_invoices_prevent_dual_invoice_types
      BEFORE INSERT OR UPDATE OF booking_folio_id ON folio_invoices
      FOR EACH ROW EXECUTE FUNCTION prevent_dual_folio_invoice_types();

      CREATE TRIGGER ar_invoices_prevent_dual_invoice_types
      BEFORE INSERT OR UPDATE OF booking_folio_id ON ar_invoices
      FOR EACH ROW EXECUTE FUNCTION prevent_dual_folio_invoice_types();

      CREATE FUNCTION prevent_folio_invoice_revision_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'folio invoice revisions are immutable';
      END;
      $$;

      CREATE TRIGGER folio_invoice_revisions_immutable
      BEFORE UPDATE OR DELETE ON folio_invoice_revisions
      FOR EACH ROW EXECUTE FUNCTION prevent_folio_invoice_revision_mutation();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS folio_invoice_revisions_immutable ON folio_invoice_revisions;
      DROP FUNCTION IF EXISTS prevent_folio_invoice_revision_mutation();
      DROP TRIGGER IF EXISTS ar_invoices_prevent_dual_invoice_types ON ar_invoices;
      DROP TRIGGER IF EXISTS folio_invoices_prevent_dual_invoice_types ON folio_invoices;
      DROP FUNCTION IF EXISTS prevent_dual_folio_invoice_types();
    SQL
  end
end
