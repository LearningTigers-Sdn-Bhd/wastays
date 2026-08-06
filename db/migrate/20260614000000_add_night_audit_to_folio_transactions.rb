class AddNightAuditToFolioTransactions < ActiveRecord::Migration[8.0]
  class MigrationFolioTransaction < ActiveRecord::Base
    self.table_name = "folio_transactions"
  end

  class MigrationNightAudit < ActiveRecord::Base
    self.table_name = "night_audits"
  end

  class MigrationBookingFolio < ActiveRecord::Base
    self.table_name = "booking_folios"
  end

  def up
    add_reference :folio_transactions, :night_audit, null: true, index: true, foreign_key: { on_delete: :restrict }
    backfill_night_audit_ids
  end

  def down
    remove_reference :folio_transactions, :night_audit, foreign_key: true
  end

  private

  def backfill_night_audit_ids
    night_audit_hotels = MigrationNightAudit.pluck(:id, :hotel_id).to_h
    folio_hotels = MigrationBookingFolio.pluck(:id, :hotel_id).to_h
    skipped = 0

    MigrationFolioTransaction.where("metadata ? 'night_audit_id'").find_each do |transaction|
      night_audit_id = parsed_night_audit_id(transaction.metadata["night_audit_id"])

      if night_audit_id && night_audit_hotels[night_audit_id] == folio_hotels[transaction.booking_folio_id]
        transaction.update_columns(night_audit_id: night_audit_id)
      else
        skipped += 1
      end
    end
  end

  def parsed_night_audit_id(value)
    string_value = value.to_s
    return unless string_value.match?(/\A[1-9]\d*\z/)

    string_value.to_i
  end
end
