# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ArrivalsDeparturesPdfExportService do
  describe "#generate" do
    it "returns a valid PDF binary" do
      hotel = instance_double(
        Hotel, name: "Sample Hotel", allow_boat_information?: true,
        hotel_time_zone: ActiveSupport::TimeZone["Kuala Lumpur"]
      )
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

      pdf = described_class.new(hotel: hotel, report: report, prepared_by: "Sarah Lim").generate

      expect(pdf).to be_a(String)
      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 500
    end

    it "returns a valid PDF binary for in-house tab" do
      hotel = instance_double(
        Hotel, name: "Sample Hotel", allow_boat_information?: true,
        hotel_time_zone: ActiveSupport::TimeZone["Kuala Lumpur"]
      )
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

      pdf = described_class.new(hotel: hotel, report: report, prepared_by: "Sarah Lim", tab: "in_house").generate

      expect(pdf).to be_a(String)
      expect(pdf).to start_with("%PDF")
      expect(pdf.bytesize).to be > 500
    end

    it "prints each meal prep section on its own page with a pax total" do
      hotel = instance_double(
        Hotel, name: "Sample Hotel", allow_boat_information?: true,
        hotel_time_zone: ActiveSupport::TimeZone["Kuala Lumpur"]
      )
      row = {
        guest_name: "Meal Guest", confirmation_token: "MP-1", pax: 2, room_type: "Deluxe", room_number: "101",
        type: "Boat-in", transfer_date: "07 May 2026", formatted_boat_time: "07:00 AM", meals: %w[Breakfast]
      }
      report = double(
        "report",
        start_date: Date.new(2026, 5, 7), end_date: Date.new(2026, 5, 7), records: [ row ], total_pax: 2,
        sections: [
          { title: "Breakfast", meal: "breakfast", rows: [ row ], total_pax: 2 },
          { title: "Lunch", meal: "lunch", rows: [], total_pax: 0 },
          { title: "Dinner", meal: "dinner", rows: [], total_pax: 0 }
        ]
      )

      sections = []
      page_breaks = 0
      allow_any_instance_of(HotelPortal::Reports::Exports::PdfReportBuilder).to receive(:add_table) { |_b, **kwargs| sections << kwargs }
      allow_any_instance_of(HotelPortal::Reports::Exports::PdfReportBuilder).to receive(:start_new_page) { page_breaks += 1 }

      pdf = described_class.new(hotel: hotel, report: report, prepared_by: "Sarah Lim", tab: "meal_prep").generate

      expect(pdf).to start_with("%PDF")
      expect(sections.map { |section| section[:section_title] }).to eq(%w[Breakfast Lunch Dinner])
      expect(page_breaks).to eq(2)
      expect(sections.first[:headers]).to eq([ "Guest Name", "Pax", "Room Number", "Transfer", "Transfer Date", "Transfer Time" ])
      expect(sections.first[:rows]).to eq([ [ "Meal Guest", "2", "101", "Boat-in", "07 May 2026", "07:00 AM" ] ])
      expect(sections.first[:total_row]).to eq([ "Total Pax", "2", nil, nil, nil, nil ])
      expect(sections.first[:numeric_columns]).to eq([ 1 ])
    end

    it "prints boat transfers as separate boat-in and boat-out tables" do
      hotel = instance_double(
        Hotel, name: "Sample Hotel", allow_boat_information?: true,
        hotel_time_zone: ActiveSupport::TimeZone["Kuala Lumpur"]
      )
      boat_ins = [ { booking_guest_id: 1, guest_name: "Boat Guest", room_number: "103", arrival_date: "27 Jul 2026", departure_date: "28 Jul 2026", boat_time: "07:00 AM" } ]
      boat_outs = [ { booking_guest_id: 1, guest_name: "Boat Guest", room_number: "103", arrival_date: "27 Jul 2026", departure_date: "28 Jul 2026", boat_time: "01:00 PM" } ]
      report = HotelPortal::Reports::BiboReport::Result.new(
        start_date: Date.new(2026, 7, 27),
        end_date: Date.new(2026, 7, 28),
        boat_ins: boat_ins,
        boat_outs: boat_outs,
        boat_in_count: boat_ins.size,
        boat_out_count: boat_outs.size,
        leg: nil
      )

      sections = []
      allow_any_instance_of(HotelPortal::Reports::Exports::PdfReportBuilder).to receive(:add_table) do |_builder, **kwargs|
        sections << kwargs
      end

      pdf = described_class.new(hotel: hotel, report: report, prepared_by: "Sarah Lim", tab: "bibo").generate

      expect(pdf).to start_with("%PDF")
      expect(sections.map { |section| section[:section_title] }).to eq([ "Boat-ins", "Boat-outs" ])
      expect(sections.first[:headers]).to eq([ "Guest Name", "Room Number", "Arrival Date", "Arrival Time" ])
      expect(sections.last[:headers]).to eq([ "Guest Name", "Room Number", "Departure Date", "Departure Time" ])
      expect(sections.first[:rows]).to eq([ [ "Boat Guest", "103", "27 Jul 2026", "07:00 AM" ] ])
      expect(sections.last[:rows]).to eq([ [ "Boat Guest", "103", "28 Jul 2026", "01:00 PM" ] ])

      # Both tables line up, and the guest name keeps the leftover page width.
      expect(sections.first[:column_widths]).to eq(sections.last[:column_widths])
      expect(sections.first[:column_widths].drop(1)).to all(eq(150))
      expect(sections.first[:column_widths].first).to be > 150
    end
  end
end
