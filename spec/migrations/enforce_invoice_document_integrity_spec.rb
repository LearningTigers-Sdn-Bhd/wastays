# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260728103000_enforce_invoice_document_integrity")

RSpec.describe EnforceInvoiceDocumentIntegrity do
  before(:context) do
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  after(:context) do
    ActiveRecord::Migration.suppress_messages { described_class.new.down }
  end

  it "rejects direct SQL updates to folio invoice revisions" do
    revision = create(:folio_invoice).current_revision

    expect { revision.update_columns(snapshot: { changed: true }) }
      .to raise_error(ActiveRecord::StatementInvalid, /folio invoice revisions are immutable/)
  end

  it "rejects direct SQL deletions of folio invoice revisions" do
    revision = create(:folio_invoice).current_revision

    expect { FolioInvoiceRevision.where(id: revision.id).delete_all }
      .to raise_error(ActiveRecord::StatementInvalid, /folio invoice revisions are immutable/)
  end

  it "prevents an AR invoice from being inserted for a folio with a folio invoice" do
    hotel = create(:hotel, hotel_prefix: "INT")
    relationship = create(:hotel_corporate_account, hotel:)
    booking = create(:booking, hotel:)
    folio = create(:booking_folio,
      booking:,
      hotel:,
      status: "closed",
      is_primary: false,
      folio_type: "external",
      payer_type: "company",
      hotel_corporate_account: relationship)
    create(:folio_invoice, booking_folio: folio)

    expect do
      ArInvoice.insert_all!([ {
        hotel_id: hotel.id,
        booking_folio_id: folio.id,
        hotel_corporate_account_id: relationship.id,
        invoice_number: 99_999,
        invoice_year: Date.current.year,
        invoice_reference: "INT-AR-#{Date.current.year}-99999",
        amount: 100,
        paid_amount: 0,
        outstanding_amount: 100,
        currency: folio.currency,
        status: "open",
        issued_on: Date.current,
        due_on: Date.current + 30.days,
        metadata: {},
        created_at: Time.current,
        updated_at: Time.current
      } ])
    end.to raise_error(ActiveRecord::StatementInvalid, /cannot have both an AR invoice and a folio invoice/)
  end
end
