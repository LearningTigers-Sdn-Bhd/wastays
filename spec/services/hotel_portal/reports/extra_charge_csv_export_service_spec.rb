# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe HotelPortal::Reports::ExtraChargeCsvExportService do
  describe "#generate" do
    it "exports rows and totals" do
      report = double(
        "report",
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

      csv = described_class.new(report: report).generate
      rows = CSV.parse(csv, headers: true)

      expect(rows.headers).to include("Posting Date", "Booking Ref", "Amount (MYR)")
      expect(rows[0]["Guest Name"]).to eq("Jane Doe")
      expect(csv).to include("TOTAL")
      expect(csv).to include("25.00")
    end
  end
end
