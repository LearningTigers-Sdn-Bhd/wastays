# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe HotelPortal::Reports::OutstandingBalanceCsvExportService do
  describe "#generate" do
    it "exports rows and total amount" do
      report = double(
        "report",
        rows: [
          {
            guest_name: "Guest A",
            confirmation_token: "WS-ABC",
            stay_dates: "07 May 2026 - 08 May 2026",
            room_details: "1x Executive King",
            room_numbers: "101",
            payment_status: "Pending",
            outstanding_amount: 220.to_d,
            latest_note: "Pay at desk"
          }
        ],
        totals: {
          outstanding_amount: 220.to_d
        }
      )

      csv = described_class.new(report: report).generate
      rows = CSV.parse(csv, headers: true)

      expect(rows.headers).to eq([ "Guest Name", "Booking Ref", "Stay", "Rooms", "Room Numbers", "Payment Status", "Outstanding Amount", "Notes" ])
      expect(rows[0]["Guest Name"]).to eq("Guest A")
      expect(rows[1]["Guest Name"]).to eq("TOTAL")
      expect(rows[1]["Outstanding Amount"]).to eq("220.00")
    end
  end
end
