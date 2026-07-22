# frozen_string_literal: true

require "rails_helper"
require "zip"

RSpec.describe HotelPortal::Reports::OutstandingBalanceExcelExportService do
  describe "#generate" do
    it "builds summary and details worksheets" do
      report = double(
        "report",
        start_date: Date.new(2026, 5, 7),
        end_date: Date.new(2026, 5, 8),
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

      hotel = instance_double(Hotel, name: "Sample Hotel", default_currency: "MYR")
      content = described_class.new(hotel: hotel, report: report).generate
      xml = []
      Zip::File.open_buffer(StringIO.new(content)) { |archive| archive.each { |entry| xml << entry.get_input_stream.read if entry.name.end_with?(".xml") } }
      text = xml.join.force_encoding(Encoding::UTF_8)

      expect(content).to start_with("PK")
      expect(text).to include("Outstanding Balance Report", "Outstanding Bookings", "Guest A")
    end
  end
end
