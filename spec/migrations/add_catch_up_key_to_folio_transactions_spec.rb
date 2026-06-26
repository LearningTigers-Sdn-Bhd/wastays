# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260615000001_add_catch_up_key_to_folio_transactions")

RSpec.describe AddCatchUpKeyToFolioTransactions do
  it "backfills catch_up_key from metadata" do
    transaction = create(:folio_transaction, catch_up_key: nil, metadata: { catch_up_key: "catch_up:1:2026-06-10:accommodation:1" })

    described_class.new.send(:backfill_catch_up_keys)

    expect(transaction.reload.catch_up_key).to eq("catch_up:1:2026-06-10:accommodation:1")
  end

  it "detects duplicate catch_up_key values within the same folio" do
    folio = create(:booking_folio)
    key = "catch_up:#{folio.booking_id}:2026-06-10:accommodation:1"
    create(:folio_transaction, booking_folio: folio, catch_up_key: key)

    expect {
      create(:folio_transaction, booking_folio: folio, catch_up_key: key)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
