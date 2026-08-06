# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::DailyOccupancyPdfExportService do
  describe "#generate" do
    it "returns a valid PDF binary" do
      hotel = instance_double(Hotel, name: "Sample Hotel", default_currency: "MYR")
      report = double(
        "report",
        start_date: Date.new(2026, 5, 6),
        end_date: Date.new(2026, 5, 7),
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

      pdf = described_class.new(hotel: hotel, report: report).generate

      expect(pdf).to be_a(String)
      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 500
    end
  end
end
