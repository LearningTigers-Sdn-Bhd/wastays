# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::SstExcelExportService do
  describe "#generate" do
    it "returns valid XML with summary and detail worksheets" do
      report = double(
        "report",
        start_date: Date.new(2026, 5, 1),
        end_date: Date.new(2026, 5, 31),
        rows: [
          {
            invoice_number: "INV-001",
            guest_name: "Guest A",
            check_in: Date.new(2026, 5, 1),
            check_out: Date.new(2026, 5, 3),
            taxable_amount: 400.to_d,
            sst_amount: 32.to_d,
            total_amount: 432.to_d
          }
        ],
        totals: {
          booking_count: 1,
          taxable_amount: 400.to_d,
          sst_amount: 32.to_d,
          total_amount: 432.to_d
        }
      )

      xml = described_class.new(report: report).generate

      expect(xml).to include("SST Report")
      expect(xml).to include("Summary")
      expect(xml).to include("Guest A")
      expect(xml).to include("32.00")
    end
  end
end
