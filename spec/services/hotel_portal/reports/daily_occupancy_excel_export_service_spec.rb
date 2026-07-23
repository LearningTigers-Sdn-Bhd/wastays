# frozen_string_literal: true

require "rails_helper"
require "zip"

RSpec.describe HotelPortal::Reports::DailyOccupancyExcelExportService do
  describe "#generate" do
    it "builds summary and daily occupancy worksheets" do
      report = double(
        "report",
        start_date: Date.new(2026, 5, 6),
        end_date: Date.new(2026, 5, 6),
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
      hotel = instance_double(Hotel, name: "Sample Hotel", default_currency: "MYR")

      content = described_class.new(hotel: hotel, report: report).generate
      xml = []
      Zip::File.open_buffer(StringIO.new(content)) { |archive| archive.each { |entry| xml << entry.get_input_stream.read if entry.name.end_with?(".xml") } }
      text = xml.join.force_encoding(Encoding::UTF_8)

      expect(content).to start_with("PK")
      expect(text).to include("Daily Occupancy Report", "Daily Occupancy", "Rooms Sold")
    end
  end
end
