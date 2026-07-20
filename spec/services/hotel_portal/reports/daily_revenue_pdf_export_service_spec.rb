# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenuePdfExportService do
  it "generates a valid pdf" do
    report = instance_double(
      HotelPortal::Reports::DailyRevenueReport::Result,
      start_date: Date.new(2026, 5, 6),
      end_date: Date.new(2026, 5, 7),
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

    hotel = instance_double(Hotel, name: "Sample Hotel")
    pdf = described_class.new(hotel: hotel, report: report).generate

    expect(pdf).to start_with("%PDF")
  end

  it "appends a transaction register page with service identity and reversal status" do
    hotel = create(:hotel)
    booking = create(:booking, hotel: hotel)
    folio = create(:booking_folio, booking: booking, hotel: hotel)
    code = create(:transaction_code, hotel: hotel, code: "CHARTER_BOAT", name: "Charter Boat", kind: "charge", category: "other")
    transaction = create(:folio_transaction, booking_folio: folio, transaction_code: code, category: "other", amount: 280)

    report = HotelPortal::Reports::DailyRevenueReport.new(hotel: hotel, start_date: transaction.posting_date, end_date: transaction.posting_date).call

    pdf = described_class.new(hotel: hotel, report: report, transactions: [ transaction ]).generate
    text = PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n")

    expect(text).to include("All Transactions")
    expect(text).to include("Charter Boat")
    expect(text).to include("Original")
  end
end
