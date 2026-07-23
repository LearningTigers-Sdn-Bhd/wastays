# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe HotelPortal::Reports::SstCsvExportService do
  describe "#generate" do
    it "exports rows and totals" do
      report = double(
        "report",
        rows: [
          {
            invoice_number: "INV-001",
            guest_name: "Guest A",
            check_in: Date.new(2026, 5, 1),
            check_out: Date.new(2026, 5, 3),
            stay_dates: "01 May 2026 - 03 May 2026",
            taxable_amount: 400.to_d,
            sst_amount: 32.to_d,
            total_amount: 432.to_d
          }
        ],
        totals: {
          taxable_amount: 400.to_d,
          sst_amount: 32.to_d,
          total_amount: 432.to_d
        }
      )

      csv = described_class.new(report: report).generate
      rows = CSV.parse(csv.delete_prefix("\uFEFF"), headers: true)

      expect(rows.headers).to eq([ "Invoice / Ref", "Guest Name", "Check-In", "Check-Out", "Taxable Amount (MYR)", "SST 8% (MYR)", "Total (MYR)" ])
      expect(rows[0]["Invoice / Ref"]).to eq("INV-001")
      expect(rows[0]["SST 8% (MYR)"]).to eq("32.00")
      expect(rows[1]["Invoice / Ref"]).to eq("TOTAL")
      expect(rows[1]["Total (MYR)"]).to eq("432.00")
    end
  end
end
