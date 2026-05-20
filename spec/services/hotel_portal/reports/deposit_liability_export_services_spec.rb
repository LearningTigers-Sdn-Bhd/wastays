# frozen_string_literal: true

require "rails_helper"

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
          advance_deposit_amount: 300.to_d,
          earned_amount: 100.to_d,
          refund_amount: 25.to_d,
          remaining_liability: 175.to_d,
          latest_deposit_posting_date: Date.new(2026, 5, 19)
        }
      ],
      totals: {
        booking_count: 1,
        advance_deposit_amount: 300.to_d,
        earned_amount: 100.to_d,
        refund_amount: 25.to_d,
        remaining_liability: 175.to_d
      }
    )
  end

  it "generates CSV with detail and total rows" do
    csv = HotelPortal::Reports::DepositLiabilityCsvExportService.new(report: report).generate

    expect(csv).to include("Guest Name,Booking Ref,Stay,Status,Rooms,Folio,Advance Deposit,Earned,Refunds,Remaining Liability,Latest Deposit Date")
    expect(csv).to include("Export Guest")
    expect(csv).to include("TOTAL")
  end

  it "generates Excel with summary and deposit liability worksheets" do
    xls = HotelPortal::Reports::DepositLiabilityExcelExportService.new(report: report).generate

    expect(xls).to include('ss:Name="Summary"')
    expect(xls).to include('ss:Name="Deposit Liability"')
    expect(xls).to include("Export Guest")
  end

  it "generates a PDF" do
    pdf = HotelPortal::Reports::DepositLiabilityPdfExportService.new(hotel: hotel, report: report).generate

    expect(pdf).to start_with("%PDF")
  end
end
