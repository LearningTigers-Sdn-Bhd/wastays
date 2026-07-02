# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::NonNationalPdfExportService do
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
            date_of_birth: Date.new(1988, 5, 14),
            guest_home_address: "Tokyo",
            check_in: Date.new(2026, 7, 2),
            checked_in_at: Time.zone.parse("2026-07-02 14:00"),
            check_out: Date.new(2026, 7, 4)
          }
        ],
        totals: { guest_count: 1, nights: 2 }
      )

      pdf = described_class.new(hotel: hotel, report: report).generate

      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 500
    end
  end
end
