# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ManagersFlashPdfExportService do
  let(:hotel) { create(:hotel) }
  let(:report) do
    double(
      "ManagersFlashReportResult",
      start_date: Date.new(2026, 5, 20),
      end_date: Date.new(2026, 5, 20),
      rows: [
        {
          date: Date.new(2026, 5, 20),
          rooms_sold: 5,
          rooms_available: 10,
          occupancy_rate: 0.5,
          adr: 100.0,
          revpar: 50.0,
          room_revenue: 500.0,
          tax_amount: 50.0,
          total_revenue: 550.0
        }
      ],
      totals: {
        rooms_sold: 5,
        rooms_available: 10,
        occupancy_rate: 0.5,
        adr: 100.0,
        revpar: 50.0,
        room_revenue: 500.0,
        tax_amount: 50.0,
        total_revenue: 550.0
      }
    )
  end

  subject { described_class.new(hotel: hotel, report: report) }

  describe "#generate" do
    it "generates a PDF content" do
      pdf_content = subject.generate
      expect(pdf_content).to start_with("%PDF-")

      # We can't easily inspect the PDF content without a PDF parser,
      # but we can verify it doesn't crash and returns a valid PDF header.
      # Deep assertions for PDF are often brittle, but we can check for some strings if we use a parser
      # For now, verifying the generation and basic PDF structure is a good improvement over a skip.
    end
  end
end
