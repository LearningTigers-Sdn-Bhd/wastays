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

    it "names each meal prep row's entitlements in a column and totals pax under Pax" do
      report = double(
        "report",
        total_pax: 5,
        records: [
          {
            guest_name: "Meal Guest", confirmation_token: "MP-1", pax: 3, room_type: "Deluxe", room_number: "101",
            type: "Boat-in", transfer_date: "07 May 2026", formatted_boat_time: "07:00 AM", meals: %w[Breakfast Lunch Dinner]
          },
          {
            guest_name: "Late Guest", confirmation_token: "MP-2", pax: 2, room_type: "Suite", room_number: "205",
            type: "Boat-out", transfer_date: "08 May 2026", formatted_boat_time: "01:00 PM", meals: %w[Breakfast]
          }
        ]
      )

      csv = described_class.new(report: report, tab: "meal_prep").generate
      table = CSV.parse(csv.delete_prefix("﻿"), headers: true)

      expect(table.headers).to eq([ "Guest Name", "Room Number", "Transfer", "Transfer Date", "Transfer Time", "Pax", "Meal Preps" ])
      expect(table[0].fields).to eq([ "Meal Guest", "101", "Boat-in", "07 May 2026", "07:00 AM", "3", "Breakfast, Lunch, Dinner" ])
      expect(table[1].fields).to eq([ "Late Guest", "205", "Boat-out", "08 May 2026", "01:00 PM", "2", "Breakfast" ])

      # The total lands under Pax, not wherever the column count happens to put it.
      total = table[2]
      expect(total["Guest Name"]).to eq("Total Pax")
      expect(total["Pax"]).to eq("5")
      expect(total["Transfer Time"]).to be_nil
    end

    it "pairs both boat legs of a guest onto one row for the bibo tab" do
      report = double(
        "report",
        boat_ins: [
          { booking_guest_id: 1, guest_name: "Both Legs", room_number: "103", arrival_date: "27 Jul 2026", departure_date: "28 Jul 2026", boat_time: "07:00 AM" },
          { booking_guest_id: 2, guest_name: "In Only", room_number: "104", arrival_date: "28 Jul 2026", departure_date: "30 Jul 2026", boat_time: "08:00 AM" }
        ],
        boat_outs: [
          { booking_guest_id: 1, guest_name: "Both Legs", room_number: "103", arrival_date: "27 Jul 2026", departure_date: "28 Jul 2026", boat_time: "01:00 PM" },
          { booking_guest_id: 3, guest_name: "Out Only", room_number: "105", arrival_date: "25 Jul 2026", departure_date: "27 Jul 2026", boat_time: "02:30 PM" }
        ]
      )

      csv = described_class.new(report: report, tab: "bibo").generate
      rows = CSV.parse(csv.delete_prefix("﻿"), headers: true)

      expect(rows.headers).to eq([ "Guest Name", "Room Number", "Arrival Date", "Departure Date", "Arrival Time", "Departure Time" ])
      expect(rows.count).to eq(3)
      expect(rows[0].fields).to eq([ "Both Legs", "103", "27 Jul 2026", "28 Jul 2026", "07:00 AM", "01:00 PM" ])
      expect(rows[1].fields).to eq([ "In Only", "104", "28 Jul 2026", "30 Jul 2026", "08:00 AM", "—" ])
      expect(rows[2].fields).to eq([ "Out Only", "105", "25 Jul 2026", "27 Jul 2026", "—", "02:30 PM" ])
    end

    it "carries only the selected leg's own columns when the bibo tab is narrowed" do
      boat_outs = [ { booking_guest_id: 1, guest_name: "Out Only", room_number: "105", arrival_date: "25 Jul 2026", departure_date: "27 Jul 2026", boat_time: "02:30 PM" } ]
      report = HotelPortal::Reports::BiboReport::Result.new(
        start_date: Date.new(2026, 7, 25), end_date: Date.new(2026, 7, 27),
        boat_ins: [], boat_outs: boat_outs, boat_in_count: 0, boat_out_count: 1, leg: "boat_outs"
      )

      csv = described_class.new(report: report, tab: "bibo").generate
      rows = CSV.parse(csv.delete_prefix("﻿"), headers: true)

      expect(rows.headers).to eq([ "Guest Name", "Room Number", "Departure Date", "Departure Time" ])
      expect(rows.count).to eq(1)
      expect(rows[0].fields).to eq([ "Out Only", "105", "27 Jul 2026", "02:30 PM" ])
    end
  end
end
