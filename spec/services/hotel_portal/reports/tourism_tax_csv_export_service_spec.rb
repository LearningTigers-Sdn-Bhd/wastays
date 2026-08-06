# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe HotelPortal::Reports::TourismTaxCsvExportService do
  describe "#generate" do
    it "exports tax rows and totals" do
      report = double(
        "report",
        rows: [
          {
            guest_name: "Kenji Sato",
            guest_country: "Japan",
            booking_reference: "BK-001",
            check_in: Date.new(2026, 7, 2),
            check_out: Date.new(2026, 7, 4),
            nights: 2,
            tax_due: 20,
            tax_collected: 20,
            collection_status: "Collected"
          }
        ],
        totals: { guest_count: 1, total_due: 20, total_collected: 20 }
      )

      csv = described_class.new(report: report).generate
      rows = CSV.parse(csv.delete_prefix("\uFEFF"), headers: true)

      expect(rows.headers).to include("Guest Name", "Tax Due (MYR)", "Collection Status")
      expect(rows[0]["Guest Name"]).to eq("Kenji Sato")
      expect(rows[0]["Collection Status"]).to eq("Collected")
      expect(csv).to include("20.00")
    end
  end
end
