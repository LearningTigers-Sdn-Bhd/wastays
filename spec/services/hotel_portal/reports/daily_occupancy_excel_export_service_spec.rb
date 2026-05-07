# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyOccupancyExcelExportService do
  describe "#generate" do
    it "builds summary and daily occupancy worksheets" do
      report = double(
        "report",
        rows: [
          {
            date: Date.new(2026, 5, 6),
            rooms_sold: 2,
            rooms_available: 8,
            occupancy_rate: 0.25.to_d,
            room_revenue: 150.to_d,
            adr: 75.to_d,
            revpar: 18.75.to_d
          }
        ],
        totals: {
          rooms_sold: 2,
          rooms_available: 8,
          occupancy_rate: 0.25.to_d,
          room_revenue: 150.to_d,
          adr: 75.to_d,
          revpar: 18.75.to_d
        }
      )

      xml = described_class.new(report: report).generate

      expect(xml).to include("<?xml version=\"1.0\"?>")
      expect(xml).to include('Worksheet ss:Name="Summary"')
      expect(xml).to include('Worksheet ss:Name="Daily Occupancy"')
      expect(xml).to include("25.00%")
    end
  end
end
