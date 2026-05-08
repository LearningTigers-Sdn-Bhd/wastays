# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyRevenueCsvExportService do
  it "generates csv" do
    report = instance_double(
      HotelPortal::Reports::DailyRevenueReport::Result,
      rows: [
        {
          date: Date.new(2026, 5, 6),
          booking_count: 2,
          room_revenue: 400.to_d,
          tax_amount: 10.to_d,
          total_revenue: 410.to_d
        }
      ]
    )

    csv = described_class.new(report: report).generate
    expect(csv).to include("Date,Bookings,Room Revenue,Tax,Total Revenue")
    expect(csv).to include("2026-05-06,2,MYR 400.00,MYR 10.00,MYR 410.00")
  end
end
