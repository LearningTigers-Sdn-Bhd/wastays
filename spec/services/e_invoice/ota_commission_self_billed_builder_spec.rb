# frozen_string_literal: true

require "rails_helper"

RSpec.describe EInvoice::OtaCommissionSelfBilledBuilder do
  let(:hotel) { create(:hotel, tin: "C9988776655", ssm_number: "202399887766") }
  let!(:setting) do
    create(:e_invoice_setting, hotel: hotel)
  end
  let(:source) { BookingSource.find_by_source("agoda") }
  let(:period_start) { Date.new(2026, 7, 1) }

  before { BookingSource.seed_defaults! }

  subject(:document) do
    described_class.new(hotel: hotel, source: source, period_start: period_start,
      amount: 86.40.to_d, booking_count: 2).build
  end

  def payload
    JSON.parse(Base64.strict_decode64(document[:document])).dig("Invoice", 0)
  end

  it "is a self-billed invoice" do
    expect(payload.dig("InvoiceTypeCode", 0, "_")).to eq("11")
  end

  # LHDN has no record of an overseas supplier, so it prescribes placeholders.
  it "names the OTA as supplier using the foreign-supplier identifiers" do
    supplier = payload.dig("AccountingSupplierParty", 0, "Party", 0)

    expect(supplier.dig("PartyLegalEntity", 0, "RegistrationName", 0, "_")).to eq("Agoda Company Pte. Ltd.")
    expect(supplier.dig("PartyIdentification", 0, "ID", 0, "_")).to eq("EI00000000030")
    expect(supplier.dig("PartyIdentification", 1, "ID", 0, "_")).to eq("NA")
    expect(supplier.dig("PostalAddress", 0, "Country", 0, "IdentificationCode", 0, "_")).to eq("SGP")
    expect(supplier.dig("PostalAddress", 0, "CountrySubentityCode", 0, "_")).to eq("17")
  end

  # The hotel is the buyer here: it is buying a service from the OTA.
  it "names the hotel as the buyer" do
    buyer = payload.dig("AccountingCustomerParty", 0, "Party", 0)

    expect(buyer.dig("PartyIdentification", 0, "ID", 0, "_")).to eq("C9988776655")
    expect(buyer.dig("PartyIdentification", 1, "ID", 0, "_")).to eq("202399887766")
  end

  it "carries the commission amount and the period it covers" do
    expect(payload.dig("LegalMonetaryTotal", 0, "PayableAmount", 0, "_")).to eq(86.40)
    expect(payload.dig("InvoicePeriod", 0, "StartDate", 0, "_")).to eq("2026-07-01")
    expect(payload.dig("InvoicePeriod", 0, "EndDate", 0, "_")).to eq("2026-07-31")
  end

  it "says what the charge is for" do
    description = payload.dig("InvoiceLine", 0, "Item", 0, "Description", 0, "_")

    expect(description).to include("Agoda Company Pte. Ltd.")
    expect(description).to include("July 2026")
    expect(description).to include("2 bookings")
  end

  it "identifies the document by hotel, OTA and month" do
    expect(document[:codeNumber]).to eq("SB-AGODA-202607-#{hotel.id}")
  end

  it "refuses to build a document for nothing" do
    builder = described_class.new(hotel: hotel, source: source, period_start: period_start,
      amount: 0.to_d, booking_count: 0)

    expect { builder.build }.to raise_error(ArgumentError, /must be positive/)
  end
end
