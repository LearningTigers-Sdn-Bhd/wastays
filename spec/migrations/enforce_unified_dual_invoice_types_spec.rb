# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260729090000_enforce_unified_dual_invoice_types")

RSpec.describe EnforceUnifiedDualInvoiceTypes do
  before(:context) do
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  after(:context) do
    ActiveRecord::Migration.suppress_messages { described_class.new.down }
  end

  let(:hotel) { create(:hotel, hotel_prefix: "DUP") }
  let(:relationship) { create(:hotel_corporate_account, hotel:) }
  let(:booking) { create(:booking, hotel:) }
  let(:folio) do
    create(:booking_folio,
      booking:,
      hotel:,
      status: "closed",
      is_primary: false,
      folio_type: "external",
      payer_type: "company",
      hotel_corporate_account: relationship)
  end

  def insert_receivable!(invoice_id: nil)
    ArInvoice.insert_all!([ {
      hotel_id: hotel.id,
      booking_folio_id: folio.id,
      hotel_corporate_account_id: relationship.id,
      invoice_id: invoice_id,
      invoice_number: 99_999,
      invoice_year: Date.current.year,
      invoice_reference: "DUP-AR-#{Date.current.year}-99999",
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
  end

  it "prevents a receivable from being inserted for a folio with a settled invoice" do
    create(:invoice, booking_folio: folio, hotel:)

    expect { insert_receivable! }
      .to raise_error(ActiveRecord::StatementInvalid, /cannot have both an AR invoice and a settled invoice/)
  end

  it "prevents a settled invoice from being created for a folio with an unlinked receivable" do
    insert_receivable!

    expect { create(:invoice, booking_folio: folio, hotel:) }
      .to raise_error(ActiveRecord::StatementInvalid, /cannot have both an AR invoice and a settled invoice/)
  end

  it "allows a direct-bill invoice to coexist with its receivable" do
    expect { create(:ar_invoice, booking_folio: folio, hotel:, hotel_corporate_account: relationship) }
      .not_to raise_error

    expect(folio.reload.invoice).to be_kind_direct_bill
    expect(folio.receivable).to be_present
  end

  it "rejects promoting a direct-bill invoice to settled while a receivable exists" do
    receivable = create(:ar_invoice, booking_folio: folio, hotel:, hotel_corporate_account: relationship)

    expect { Invoice.where(id: receivable.invoice_id).update_all(kind: "settled") }
      .to raise_error(ActiveRecord::StatementInvalid, /cannot have both an AR invoice and a settled invoice/)
  end
end
