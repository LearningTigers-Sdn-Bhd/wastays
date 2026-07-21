# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe HotelPortal::Reports::DailyOccupancyCsvExportService do
  describe "#generate" do
    it "exports daily rows and totals" do
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
            revpar: 18.75.to_d,
            tax_amount: 10.to_d,
            total_revenue: 160.to_d
          }
        ],
        totals: {
          rooms_sold: 2,
          rooms_available: 8,
          occupancy_rate: 0.25.to_d,
          room_revenue: 150.to_d,
          adr: 75.to_d,
          revpar: 18.75.to_d,
          tax_amount: 10.to_d,
          total_revenue: 160.to_d
        }
      )

      csv = described_class.new(report: report).generate
      rows = CSV.parse(csv, headers: true)

      expect(rows.count).to eq(2)
      expect(rows.headers).to eq([ "Date", "Rooms Sold", "Rooms Available", "Occupancy %", "Room Revenue", "Average Daily Rate (ADR)", "Revenue per Available Room (RevPAR)", "Tax", "Total Revenue" ])
      expect(rows[0]["Date"]).to eq("2026-05-06")
      expect(rows[0]["Occupancy %"]).to eq("25.00%")
      expect(rows[1]["Date"]).to eq("TOTAL")
    end
  end
end
