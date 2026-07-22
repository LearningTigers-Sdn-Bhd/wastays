# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ArrivalsDeparturesExcelExportService do
  describe "#generate" do
    let(:hotel) { instance_double(Hotel, name: "Sample Hotel", default_currency: "MYR") }

    it "builds an XLSX workbook with arrivals by default" do
      report = double(
        "report",
        start_date: Date.new(2026, 5, 6), end_date: Date.new(2026, 5, 8),
        arrivals: [
          {
            guest_name: "Arrival & Guest",
            confirmation_token: "ARR-123",
            room_details: "1x Deluxe",
            room_numbers: "101",
            stay_dates: "06 May 2026 - 08 May 2026",
            pre_checkin_status: "Not started",
            guarantee_method_status: "None",
            deposit_status: "Not required",
            latest_note: "VIP"
          }
        ],
        departures: [
          {
            guest_name: "Departure Guest",
            confirmation_token: "DEP-456",
            room_details: "1x Suite",
            room_numbers: "205",
            stay_dates: "04 May 2026 - 07 May 2026",
            departure_status: "Checked out 11:58 AM",
            latest_note: nil
          }
        ]
      )

      content = described_class.new(hotel: hotel, report: report).generate

      expect(content).to start_with("PK")
    end

    it "builds a single checkout worksheet for checkout tab" do
      report = double("report", start_date: Date.new(2026, 5, 6), end_date: Date.new(2026, 5, 8), arrivals: [], in_house: [], departures: [], checkout: [])

      body = described_class.new(hotel: hotel, report: report, tab: "checkout").generate

      expect(body).to start_with("PK")
    end
  end
end
