# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::OutstandingBalanceExcelExportService do
  describe "#generate" do
    it "builds summary and details worksheets" do
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
          booking_count: 1,
          outstanding_amount: 220.to_d
        }
      )

      xml = described_class.new(report: report).generate

      expect(xml).to include("<?xml version=\"1.0\"?>")
      expect(xml).to include('Worksheet ss:Name="Summary"')
      expect(xml).to include('Worksheet ss:Name="Outstanding Balances"')
      expect(xml).to include("220.00")
    end
  end
end
