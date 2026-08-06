# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::TourismTaxPdfExportService do
  describe "#generate" do
    it "renders a pdf blob" do
      hotel = build_stubbed(:hotel, name: "Sample Hotel")
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

      pdf = described_class.new(hotel: hotel, report: report).generate

      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 500
    end
  end
end
