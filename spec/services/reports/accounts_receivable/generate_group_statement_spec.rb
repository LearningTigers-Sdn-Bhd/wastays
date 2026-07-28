# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe Reports::AccountsReceivable::GenerateGroupStatement do
  let(:hotel) { create(:hotel, hotel_prefix: "GST") }
  let(:group) { create(:group_booking, hotel:) }
  let(:relationship) { create(:hotel_corporate_account, hotel:) }

  it "renders only explicitly selected AR invoices without creating records" do
    first = ar_invoice_for(booking_for(1), amount: 125)
    second = ar_invoice_for(booking_for(2), amount: 75)

    expect do
      pdf = described_class.new(
        hotel:,
        group_booking: group,
        ar_invoice_ids: [ first.id, second.id ],
        printed_by: "Finance User"
      ).generate
      text = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")

      expect(text).to include("GROUP ACCOUNTS RECEIVABLE STATEMENT")
      expect(text).to include(first.formatted_invoice_number, second.formatted_invoice_number, "200.00")
    end.not_to change(ArInvoice, :count)
  end

  it "rejects duplicates, void invoices, and mixed currencies" do
    first = ar_invoice_for(booking_for(1), amount: 100)
    second = ar_invoice_for(booking_for(2), amount: 100, currency: "USD")

    expect { generate([ first.id, first.id ]) }.to raise_error(described_class::ValidationError, /Duplicate/)
    expect { generate([ first.id, second.id ]) }.to raise_error(described_class::ValidationError, /one currency/)

    first.update!(status: "void")
    expect { generate([ first.id ]) }.to raise_error(described_class::ValidationError, /Voided/)
  end

  def booking_for(position)
    create(:booking, hotel:, group_booking: group, group_position: position)
  end

  def ar_invoice_for(booking, amount:, currency: "MYR")
    folio = create(:booking_folio,
      booking:,
      hotel:,
      status: "closed",
      is_primary: false,
      folio_type: "external",
      payer_type: "company",
      currency:,
      hotel_corporate_account: relationship)
    create(:ar_invoice, booking_folio: folio, hotel:, hotel_corporate_account: relationship, amount:, currency:)
  end

  def generate(ids)
    described_class.new(hotel:, group_booking: group, ar_invoice_ids: ids).generate
  end
end
