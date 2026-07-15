# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ArrivalsDeparturesPdfExportService do
  describe "#generate" do
    it "returns a valid PDF binary" do
      hotel = instance_double(Hotel, name: "Sample Hotel", allow_boat_information?: true)
      report = double(
        "report",
        start_date: Date.new(2026, 5, 6),
        end_date: Date.new(2026, 5, 7),
        arrival_count: 1,
        in_house_count: 0,
        departure_count: 1,
        checkout_count: 0,
        arrivals: [
          {
            guest_name: "Arrival Guest",
            confirmation_token: "ARR-123",
            room_details: "1x Deluxe",
            room_numbers: "101",
            stay_dates: "06 May 2026 - 08 May 2026",
            pre_checkin_status: "Not started",
            guarantee_status: "None / Not required",
            latest_note: "Late check-in"
          }
        ],
        in_house: [],
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
        ],
        checkout: []
      )

      pdf = described_class.new(hotel: hotel, report: report).generate

      expect(pdf).to be_a(String)
      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 500
    end

    it "returns a valid PDF binary for in-house tab" do
      hotel = instance_double(Hotel, name: "Sample Hotel", allow_boat_information?: true)
      report = double(
        "report",
        start_date: Date.new(2026, 5, 6),
        end_date: Date.new(2026, 5, 7),
        arrival_count: 1,
        in_house_count: 1,
        departure_count: 1,
        checkout_count: 1,
        arrivals: [],
        in_house: [
          {
            guest_name: "In House Guest",
            confirmation_token: "IN-123",
            room_details: "1x Deluxe",
            room_numbers: "101",
            stay_dates: "06 May 2026 - 08 May 2026",
            departure_status: "In house",
            latest_note: "VIP"
          }
        ],
        departures: [],
        checkout: []
      )

      pdf = described_class.new(hotel: hotel, report: report, tab: "in_house").generate

      expect(pdf).to be_a(String)
      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 500
    end
  end
end
