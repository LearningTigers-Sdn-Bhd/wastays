# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe HotelPortal::Reports::ArrivalsDeparturesCsvExportService do
  describe "#generate" do
    it "exports arrivals rows with expanded status columns by default" do
      report = double(
        "report",
        arrivals: [
          {
            guest_name: "Arrival Guest",
            confirmation_token: "ARR-123",
            room_details: "1x Deluxe",
            room_numbers: "101",
            stay_dates: "06 May 2026 - 08 May 2026",
            pre_checkin_status: "Not started",
            guarantee_method_status: "None",
            deposit_status: "Not required",
            latest_note: "Late check-in"
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

      csv = described_class.new(report: report).generate
      rows = CSV.parse(csv.delete_prefix("\uFEFF"), headers: true)

      expect(rows.count).to eq(1)
      expect(rows.headers).to eq([
        "Section",
        "Guest Name",
        "Booking Ref",
        "Rooms",
        "Room Numbers",
        "Stay",
        "Pre-checkin Status",
        "Guarantee Method",
        "Deposit Status",
        "Departure Status",
        "Notes"
      ])

      expect(rows[0]["Section"]).to eq("Arrival")
      expect(rows[0]["Pre-checkin Status"]).to eq("Not started")
      expect(rows[0]["Guarantee Method"]).to eq("None")
      expect(rows[0]["Deposit Status"]).to eq("Not required")
      expect(rows[0]["Departure Status"]).to be_nil
    end

    it "exports only checkout rows for checkout tab" do
      report = double(
        "report",
        arrivals: [],
        in_house: [],
        departures: [],
        checkout: [
          {
            guest_name: "Checked Out Guest",
            confirmation_token: "CHK-123",
            room_details: "1x Deluxe",
            room_numbers: "101",
            stay_dates: "06 May 2026 - 07 May 2026",
            departure_status: "Checked out 11:58 AM",
            latest_note: nil
          }
        ]
      )

      csv = described_class.new(report: report, tab: "checkout").generate

      expect(csv).to include("Checked Out Guest")
      expect(csv).not_to include("Arrival")
    end
  end
end
