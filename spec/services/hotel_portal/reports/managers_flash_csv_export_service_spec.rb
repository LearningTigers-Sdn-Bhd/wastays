# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ManagersFlashCsvExportService do
  let(:hotel) { create(:hotel) }
  let(:report) do
    double(
      "ManagersFlashReportResult",
      rows: [
        {
          date: Date.new(2026, 5, 20),
          rooms_sold: 5,
          rooms_available: 10,
          occupancy_rate: 0.5,
          adr: 100.0,
          revpar: 50.0,
          room_revenue: 500.0,
          tax_amount: 50.0,
          total_revenue: 550.0
        }
      ],
      totals: {
        rooms_sold: 5,
        rooms_available: 10,
        occupancy_rate: 0.5,
        adr: 100.0,
        revpar: 50.0,
        room_revenue: 500.0,
        tax_amount: 50.0,
        total_revenue: 550.0
      }
    )
  end

  subject { described_class.new(report: report) }

  describe "#generate" do
    it "generates a CSV with correct headers and data" do
      csv_content = subject.generate
      rows = CSV.parse(csv_content)

      expect(rows[0]).to eq([ "Date", "Rooms Sold", "Rooms Available", "Occupancy %", "Average Daily Rate (ADR)", "Revenue per Available Room (RevPAR)", "Room Revenue", "Tax", "Total Revenue" ])

      data_row = rows[1]
      expect(data_row[0]).to eq("2026-05-20")
      expect(data_row[1]).to eq("5")
      expect(data_row[3]).to eq("50.00%")
      expect(data_row[6]).to eq("500.00")
      expect(data_row[8]).to eq("550.00")

      total_row = rows[2]
      expect(total_row[0]).to eq("TOTAL")
      expect(total_row[8]).to eq("550.00")
    end
  end
end
