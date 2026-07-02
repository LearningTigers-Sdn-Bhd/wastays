# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ExtraChargePdfExportService do
  describe "#generate" do
    it "renders a pdf blob" do
      hotel = build_stubbed(:hotel, name: "Sample Hotel")
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

      pdf = described_class.new(hotel: hotel, report: report).generate

      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 500
    end
  end
end
