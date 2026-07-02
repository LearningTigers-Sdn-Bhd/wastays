# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::TourismTaxExcelExportService do
  describe "#generate" do
    it "builds workbook content" do
      report = double(
        "report",
        start_date: Date.new(2026, 7, 1),
        end_date: Date.new(2026, 7, 2),
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

      xml = described_class.new(report: report).generate

      expect(xml).to include("<Workbook")
      expect(xml).to include("Tourism Tax")
      expect(xml).to include("Kenji Sato")
      expect(xml).to include("20.00")
    end
  end
end
