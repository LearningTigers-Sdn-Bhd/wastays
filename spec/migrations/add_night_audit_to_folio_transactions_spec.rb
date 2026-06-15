# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260614000000_add_night_audit_to_folio_transactions")

RSpec.describe AddNightAuditToFolioTransactions do
  it "backfills valid metadata links and skips invalid or orphaned links" do
    audit = create(:night_audit)
    booking = create(:booking, hotel: audit.hotel)
    valid = create(:folio_transaction, booking_folio: create(:booking_folio, hotel: audit.hotel, booking: booking), metadata: { night_audit_id: audit.id })
    invalid = create(:folio_transaction, metadata: { night_audit_id: "not-an-id" })
    orphaned = create(:folio_transaction, metadata: { night_audit_id: NightAudit.maximum(:id).to_i + 10_000 })

    described_class.new.send(:backfill_night_audit_ids)

    expect(valid.reload.night_audit_id).to eq(audit.id)
    expect(invalid.reload.night_audit_id).to be_nil
    expect(orphaned.reload.night_audit_id).to be_nil
  end
end
