# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "zip"

RSpec.describe "Deposit liability export services", type: :service do
  let(:hotel) { create(:hotel, name: "Ledger Hotel") }
  let(:report) do
    HotelPortal::Reports::DepositLiabilityReport::Result.new(
      as_of_date: Date.new(2026, 5, 20),
      rows: [
        {
          guest_name: "Export Guest",
          confirmation_token: "WS-EXPORT",
          stay_dates: "20 May 2026 - 22 May 2026",
          booking_status: "Confirmed",
          room_details: "1x Deluxe",
          folio_number: "F-101",
          booking_payment_amount: 300.to_d,
          earned_amount: 100.to_d,
          refund_amount: 25.to_d,
          remaining_liability: 175.to_d,
          latest_deposit_posting_date: Date.new(2026, 5, 19)
        }
      ],
      totals: {
        booking_count: 1,
        booking_payment_amount: 300.to_d,
        earned_amount: 100.to_d,
        refund_amount: 25.to_d,
        remaining_liability: 175.to_d
      }
    )
  end

  it "generates CSV with detail and total rows" do
    csv = HotelPortal::Reports::DepositLiabilityCsvExportService.new(report: report).generate

    expect(csv).to include("Guest Name,Booking Ref,Stay,Status,Rooms,Folio,Deposit Received,Earned,Refunds,Remaining Liability,Latest Deposit Date")
    expect(csv).to include("Export Guest")
    expect(csv).to include("TOTAL")
    expect(csv).to include(HotelPortal::Reports::DepositLiabilityReport::SCOPE_NOTE)
  end

  it "generates a genuine Excel workbook" do
    xlsx = HotelPortal::Reports::DepositLiabilityExcelExportService.new(hotel: hotel, report: report).generate
    shared_strings = nil
    Zip::File.open_buffer(StringIO.new(xlsx)) do |archive|
      shared_strings = archive.find_entry("xl/sharedStrings.xml").get_input_stream.read
    end

    expect(xlsx).to start_with("PK")
    expect(shared_strings).to include(
      "Deposits Received", "Deposit Received", "Latest Deposit Date",
      HotelPortal::Reports::DepositLiabilityReport::SCOPE_NOTE
    )
    expect(shared_strings).not_to include("Booking Payments", "Booking Payment", "Latest Payment Date")
  end

  it "generates a PDF" do
    pdf = HotelPortal::Reports::DepositLiabilityPdfExportService.new(hotel: hotel, report: report, prepared_by: "Sarah Lim").generate
    text = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n").squish

    expect(pdf).to start_with("%PDF")
    expect(text).to include(
      "DEPOSITS RECEIVED", "Deposit Received", "Latest Deposit Date",
      HotelPortal::Reports::DepositLiabilityReport::SCOPE_NOTE
    )
    expect(text).not_to include("BOOKING PAYMENTS", "Booking Payment", "Latest Payment Date")
  end
end
