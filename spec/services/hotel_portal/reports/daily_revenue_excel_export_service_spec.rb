# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueExcelExportService do
  it "generates workbook with summary daily and source sheets" do
    report = instance_double(
      HotelPortal::Reports::DailyRevenueReport::Result,
      totals: {
        booking_count: 2,
        room_revenue: 400.to_d,
        tax_amount: 10.to_d,
        total_revenue: 410.to_d
      },
      rows: [
        {
          date: Date.new(2026, 5, 6),
          booking_count: 2,
          room_revenue: 400.to_d,
          tax_amount: 10.to_d,
          total_revenue: 410.to_d
        }
      ],
      source_rows: [
        {
          source: "Walk-in",
          booking_count: 2,
          room_revenue: 400.to_d,
          tax_amount: 10.to_d,
          total_revenue: 410.to_d
        }
      ]
    )

    xls = described_class.new(report: report).generate
    expect(xls).to include('Worksheet ss:Name="Summary"')
    expect(xls).to include('Worksheet ss:Name="Daily Revenue"')
    expect(xls).to include('Worksheet ss:Name="Revenue by Source"')
    expect(xls).to include('Worksheet ss:Name="All Transactions"')
  end

  it "lists custom service identity and signed amounts on the All Transactions sheet" do
    hotel = create(:hotel)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    code = create(:transaction_code, hotel: hotel, code: "ISLAND_HOP", name: "Island Hopping", kind: "charge", category: "other")
    transaction = create(:folio_transaction, booking_folio: folio, transaction_code: code, category: "other", amount: 100)
    refund = create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "refund", amount: -20)

    report = HotelPortal::Reports::DailyRevenueReport.new(hotel: hotel, start_date: transaction.posting_date, end_date: transaction.posting_date).call

    xls = described_class.new(report: report, transactions: [ transaction, refund ]).generate

    expect(xls).to include("Island Hopping")
    expect(xls).to include("ISLAND_HOP")
    expect(xls).to include("-20.00")
  end
end
