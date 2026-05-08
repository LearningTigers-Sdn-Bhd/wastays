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
end
