# frozen_string_literal: true

class EnforceUnifiedInvoiceIntegrity < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION prevent_invoice_revision_mutation()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'invoice revisions are immutable';
      END;
      $$;

      DROP TRIGGER IF EXISTS invoice_revisions_immutable ON invoice_revisions;
      CREATE TRIGGER invoice_revisions_immutable
      BEFORE UPDATE OR DELETE ON invoice_revisions
      FOR EACH ROW EXECUTE FUNCTION prevent_invoice_revision_mutation();
    SQL
  end

  def down
    execute "DROP TRIGGER IF EXISTS invoice_revisions_immutable ON invoice_revisions"
    execute "DROP FUNCTION IF EXISTS prevent_invoice_revision_mutation()"
  end
end
