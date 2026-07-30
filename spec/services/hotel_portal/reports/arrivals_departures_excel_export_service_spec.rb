# frozen_string_literal: true

require "rails_helper"
require "zip"

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

    it "gives each meal prep section its own worksheet" do
      row = {
        guest_name: "Meal Guest", confirmation_token: "MP-1", pax: 2, room_type: "Deluxe", room_number: "101",
        type: "Boat-in", transfer_date: "07 May 2026", formatted_boat_time: "07:00 AM", meals: %w[Breakfast Lunch]
      }
      report = double(
        "report",
        start_date: Date.new(2026, 5, 7), end_date: Date.new(2026, 5, 7), records: [ row ], total_pax: 2,
        sections: [
          { title: "Breakfast", meal: "breakfast", rows: [ row ], total_pax: 2 },
          { title: "Lunch", meal: "lunch", rows: [ row ], total_pax: 2 },
          { title: "Dinner", meal: "dinner", rows: [], total_pax: 0 }
        ]
      )

      body = described_class.new(hotel: hotel, report: report, tab: "meal_prep").generate

      expect(body).to start_with("PK")
      workbook_xml = nil
      Zip::File.open_buffer(StringIO.new(body)) do |archive|
        workbook_xml = archive.get_entry("xl/workbook.xml").get_input_stream.read
      end
      sheet_names = workbook_xml.scan(/<sheet [^>]*name="([^"]+)"/).flatten
      expect(sheet_names).to eq(%w[Breakfast Lunch Dinner])
    end
  end
end
