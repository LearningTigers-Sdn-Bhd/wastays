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
  end
end
