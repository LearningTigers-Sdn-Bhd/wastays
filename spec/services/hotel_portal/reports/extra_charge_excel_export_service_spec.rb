# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ExtraChargeExcelExportService do
  describe "#generate" do
    it "builds workbook content" do
      report = double(
        "report",
        start_date: Date.new(2026, 7, 1),
        end_date: Date.new(2026, 7, 2),
        active_tab: "fb",
        rows: [
          {
            posting_date: Date.new(2026, 7, 2),
            booking_reference: "BK-001",
            folio_number: "FOL-001",
            guest_name: "Jane Doe",
            description: "Mini bar",
            category: "fb",
            amount: 25
          }
        ],
        totals: { transaction_count: 1, total_amount: 25 }
      )

      xml = described_class.new(report: report).generate

      expect(xml).to include("<Workbook")
      expect(xml).to include("F&amp;B")
      expect(xml).to include("Jane Doe")
      expect(xml).to include("25.00")
    end
  end
end
