# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ArrivalsDeparturesExcelExportService do
  describe "#generate" do
    it "builds an excel xml workbook with arrivals and departures worksheets" do
      report = double(
        "report",
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

      xml = described_class.new(report: report).generate

      expect(xml).to include("<?xml version=\"1.0\"?>")
      expect(xml).to include('Worksheet ss:Name="Arrivals"')
      expect(xml).to include('Worksheet ss:Name="Departures"')
      expect(xml).to include("Arrival &amp; Guest")
      expect(xml).to include("Checked out 11:58 AM")
    end
  end
end
