# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::SstPdfExportService do
  describe "#generate" do
    it "returns a valid PDF binary" do
      hotel = instance_double(Hotel, name: "Sample Hotel", default_currency: "MYR")
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
            stay_dates: "01 May 2026 - 03 May 2026",
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

      pdf = described_class.new(hotel: hotel, report: report).generate

      expect(pdf).to be_a(String)
      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 500
    end
  end
end
