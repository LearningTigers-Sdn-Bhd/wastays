# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::ArrivalsDeparturesReport, type: :service do
  let(:hotel) { create(:hotel) }
  let(:other_hotel) { create(:hotel) }
  let(:start_date) { Date.new(2026, 5, 7) }
  let(:end_date) { Date.new(2026, 5, 7) }
  let(:service) { described_class.new(hotel: hotel, start_date: start_date, end_date: end_date) }

  describe "#call" do
    it "returns arrivals and departures for the selected hotel and date" do
      arrival = create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 2.days, guest_name: "Arrival Guest", confirmation_token: "WS-ARRIVE")
      departure = create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 2.days, check_out: start_date, guest_name: "Departure Guest", confirmation_token: "WS-DEPART")
      create(:booking, hotel: hotel, status: "confirmed", check_in: start_date + 1.day, check_out: start_date + 3.days, guest_name: "Wrong Date")
      create(:booking, hotel: other_hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, guest_name: "Other Hotel")
      create(:booking, hotel: hotel, status: "cancelled", check_in: start_date, check_out: start_date + 1.day, guest_name: "Cancelled Guest")

      result = service.call

      expect(result.start_date).to eq(start_date)
      expect(result.end_date).to eq(end_date)
      expect(result.arrival_count).to eq(1)
      expect(result.departure_count).to eq(1)
      expect(result.arrivals.map { |row| row[:booking_id] }).to eq([ arrival.id ])
      expect(result.departures.map { |row| row[:booking_id] }).to eq([ departure.id ])
    end

    it "normalizes room details, TBA room number, and latest note" do
      booking = create(:booking, hotel: hotel, status: "confirmed", check_in: start_date, check_out: start_date + 1.day, adults: 2, children: 1, confirmation_token: "WS-ROOMS")
      deluxe = create(:room_type, hotel: hotel, name: "Deluxe King")
      twin = create(:room_type, hotel: hotel, name: "Twin Share")
      create(:booking_room, booking: booking, room_type: deluxe, room_number: "301", room_type_snapshot: { "name" => "Snapshot Deluxe" })
      create_list(:booking_room, 2, booking: booking, room_type: twin, room_number: nil, room_type_snapshot: {})
      create(:booking_note, booking: booking, body: "Older note", created_at: 2.hours.ago)
      create(:booking_note, booking: booking, body: "VIP guest", created_at: 1.hour.ago)

      row = service.call.arrivals.first

      expect(row[:booking_id]).to eq(booking.id)
      expect(row[:confirmation_token]).to eq("WS-ROOMS")
      expect(row[:room_details]).to eq("1x Snapshot Deluxe, 2x Twin Share")
      expect(row[:room_numbers]).to eq("301, TBA, TBA")
      expect(row[:guest_count]).to eq("2 adults, 1 child")
      expect(row[:latest_note]).to eq("VIP guest")
    end

    it "marks completed checkout rows with checkout time" do
      booking = create(:booking, hotel: hotel, status: "completed", check_in: start_date - 1.day, check_out: start_date, checked_out_at: Time.zone.local(2026, 5, 7, 10, 30))

      row = service.call.checkout.first

      expect(row[:booking_id]).to eq(booking.id)
      expect(row[:departure_status]).to eq("Checked out 10:30 AM")
    end

    it "marks due departures that are not completed" do
      booking = create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: start_date, checked_out_at: nil)

      row = service.call.departures.first

      expect(row[:booking_id]).to eq(booking.id)
      expect(row[:departure_status]).to eq("Due out")
    end

    it "returns in-house bookings staying during the selected range" do
      in_house = create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: end_date + 1.day, guest_name: "In House Guest")
      create(:booking, hotel: hotel, status: "completed", check_in: start_date - 1.day, check_out: start_date, guest_name: "Checked Out Guest")

      result = service.call

      expect(result.in_house_count).to eq(1)
      expect(result.in_house.map { |row| row[:booking_id] }).to eq([ in_house.id ])
    end

    it "separates due departures from completed checkout rows" do
      due_out = create(:booking, hotel: hotel, status: "checked_in", check_in: start_date - 1.day, check_out: start_date, guest_name: "Due Out Guest")
      checked_out = create(:booking, hotel: hotel, status: "completed", check_in: start_date - 1.day, check_out: start_date, checked_out_at: Time.zone.local(2026, 5, 7, 10, 30), guest_name: "Checked Out Guest")

      result = service.call

      expect(result.departures.map { |row| row[:booking_id] }).to eq([ due_out.id ])
      expect(result.checkout.map { |row| row[:booking_id] }).to eq([ checked_out.id ])
      expect(result.departure_count).to eq(1)
      expect(result.checkout_count).to eq(1)
    end

    it "returns arrivals and departures across a date range" do
      range_service = described_class.new(
        hotel: hotel,
        start_date: Date.new(2026, 5, 7),
        end_date: Date.new(2026, 5, 9)
      )

      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 5, 7), check_out: Date.new(2026, 5, 8), guest_name: "Range Arrival 1")
      create(:booking, hotel: hotel, status: "checked_in", check_in: Date.new(2026, 5, 9), check_out: Date.new(2026, 5, 10), guest_name: "Range Arrival 2")
      create(:booking, hotel: hotel, status: "completed", check_in: Date.new(2026, 5, 6), check_out: Date.new(2026, 5, 8), guest_name: "Range Departure 1")
      create(:booking, hotel: hotel, status: "confirmed", check_in: Date.new(2026, 5, 6), check_out: Date.new(2026, 5, 9), guest_name: "Range Departure 2")

      result = range_service.call

      expect(result.arrival_count).to eq(2)
      expect(result.departure_count).to eq(2)
      expect(result.checkout_count).to eq(1)
    end
  end
end
