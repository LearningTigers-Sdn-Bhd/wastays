# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe Reports::AccountsReceivable::GenerateStatement do
  let(:hotel) do
    create(
      :hotel,
      name: "Hotel ABC Resort",
      address: "Jalan Pantai Cenang",
      city: "Langkawi",
      country: "Malaysia",
      contact_phone: "+60 12-345 6789",
      contact_email: "frontdesk@example.com"
    )
  end
  let(:corporate_account) { create(:account, :corporate, name: "Atlas Travel") }
  let(:relationship) do
    create(
      :hotel_corporate_account,
      hotel: hotel,
      corporate_account: corporate_account,
      credit_currency: "MYR",
      payment_terms_days: 30
    )
  end
  let!(:contact) { create(:user, :corporate, account: corporate_account, email: "billing@atlas.test") }

  it "renders the booking-invoice-style statement header, ledger, totals, aging, notes, and footer" do
    allow(hotel).to receive(:current_business_date).and_return(Date.new(2026, 6, 30))
    booking = create(:booking, hotel: hotel, confirmation_token: "BK-PDF", currency: "MYR")
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: relationship, currency: "MYR")
    invoice = create(
      :ar_invoice,
      hotel: hotel,
      booking_folio: folio,
      hotel_corporate_account: relationship,
      invoice_number: 9001,
      amount: 250,
      outstanding_amount: 250,
      currency: "MYR",
      issued_on: Date.new(2026, 6, 5),
      due_on: Date.new(2026, 6, 20)
    )
    create(
      :ar_payment,
      hotel: hotel,
      hotel_corporate_account: relationship,
      amount: 100,
      currency: "MYR",
      reference_number: "BANK-PDF-1",
      received_at: Date.new(2026, 6, 10)
    )
    report = Reports::AccountsReceivable::GenerateStatementRecords.call(
      hotel: hotel,
      hotel_corporate_account: relationship,
      start_date: Date.new(2026, 6, 1),
      end_date: Date.new(2026, 6, 30),
      currency: "MYR"
    )

    travel_to Time.zone.local(2026, 6, 30, 14, 35, 0) do
      text = pdf_text(described_class.new(report: report, printed_by: "F. Suhaila").generate)

      expect(text).to include("ACCOUNT STATEMENT")
      expect(text).to include("HOTEL INFORMATION")
      expect(text).to include("Hotel ABC Resort")
      expect(text).to include("Jalan Pantai Cenang, Langkawi, Malaysia")
      expect(text).to include("ACCOUNT DETAILS")
      expect(text).to include("Atlas Travel")
      expect(text).to include("billing@atlas.test")
      expect(text).to include("STATEMENT DETAILS")
      expect(text).to include("01 Jun 2026 - 30 Jun 2026")
      expect(text).to include(invoice.formatted_invoice_number)
      expect(text).to include("BANK-PDF-1")
      expect(text).to include("STATEMENT SUMMARY (MYR)")
      expect(text).to include("INVOICE AGING AS OF 30 JUN 2026")
      expect(text).to include("Historical statements are restated")
      expect(text).to include("Printed at 30 Jun 2026 14:35 by F. Suhaila")
      expect(text).to include("Page 1 of")
      expect(text).not_to include("Guest Signature")
    end
  end

  def pdf_text(pdf)
    PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")
  end
end
