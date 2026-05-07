# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::OutstandingBalancePdfExportService do
  describe "#generate" do
    it "returns a valid PDF binary" do
      hotel = instance_double(Hotel, name: "Sample Hotel")
      report = double(
        "report",
        start_date: Date.new(2026, 5, 7),
        end_date: Date.new(2026, 5, 8),
        rows: [
          {
            guest_name: "Guest A",
            confirmation_token: "WS-ABC",
            stay_dates: "07 May 2026 - 08 May 2026",
            payment_status: "Pending",
            outstanding_amount: 220.to_d,
            latest_note: "Pay at desk"
          }
        ],
        totals: {
          booking_count: 1,
          outstanding_amount: 220.to_d
        }
      )

      pdf = described_class.new(hotel: hotel, report: report).generate

      expect(pdf).to be_a(String)
      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 500
    end
  end
end
