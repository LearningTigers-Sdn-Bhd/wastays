# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260615000002_harden_folio_required_fields")

RSpec.describe HardenFolioRequiredFields do
  it "backfills null and blank required folio fields" do
    ActiveRecord::Base.connection.change_column_null(:folio_transactions, :description, true)
    ActiveRecord::Base.connection.change_column_null(:folio_transactions, :currency, true)
    ActiveRecord::Base.connection.change_column_null(:booking_folios, :status, true)

    hotel = create(:hotel, default_currency: "USD")
    booking = create(:booking, hotel: hotel, currency: "EUR")
    folio = create(:booking_folio, hotel: hotel, booking: booking)
    transaction = create(:folio_transaction, booking_folio: folio)

    transaction.update_columns(description: nil, currency: nil)
    folio.update_columns(status: nil)

    described_class.new.send(:backfill_required_fields)

    expect(transaction.reload.description).to eq("Legacy folio transaction ##{transaction.id}")
    expect(transaction.currency).to eq("EUR")
    expect(folio.reload.status).to eq("open")
  ensure
    described_class.new.send(:backfill_required_fields)
    ActiveRecord::Base.connection.change_column_null(:folio_transactions, :description, false)
    ActiveRecord::Base.connection.change_column_null(:folio_transactions, :currency, false)
    ActiveRecord::Base.connection.change_column_null(:booking_folios, :status, false)
  end
end
