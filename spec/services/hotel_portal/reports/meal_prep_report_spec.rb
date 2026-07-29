# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::MealPrepReport do
  let(:hotel) { create(:hotel, time_zone: "UTC") }
  let(:other_hotel) { create(:hotel, time_zone: "UTC") }
  let(:start_date) { Date.new(2026, 5, 10) }
  let(:end_date) { Date.new(2026, 5, 10) }

  # Meals are read off the slot a guest is booked on, so the timetable has to
  # exist before any booking references it.
  def slot(target_hotel, kind, time, meals)
    create(
      :hotel_boat_schedule,
      hotel: target_hotel, kind: kind, time: time,
      has_breakfast: meals.include?(:breakfast),
      has_lunch: meals.include?(:lunch),
      has_dinner: meals.include?(:dinner)
    )
  end

  before do
    slot(hotel, "boat_in", "08:00", %i[breakfast lunch dinner])
    slot(hotel, "boat_in", "09:00", %i[breakfast lunch dinner])
    slot(hotel, "boat_in", "13:00", %i[lunch dinner])
    slot(hotel, "boat_in", "18:00", %i[dinner])
    slot(hotel, "boat_out", "14:00", %i[breakfast lunch])
    slot(other_hotel, "boat_in", "09:00", %i[breakfast lunch dinner])
  end

  describe "#call" do
    it "lists boat-ins and boat-outs within the date range, sorted by time, for the correct hotel with multi-meal assignments" do
      # Booking 1: Boat-in at 8:00 AM (Breakfast, Lunch, Dinner)
      booking1 = create(:booking, hotel: hotel, adults: 2, children: 1)
      create(:booking_guest, booking: booking1, boat_in_at: Time.utc(2026, 5, 10, 8, 0, 0))

      # Booking 2: Boat-out at 2:00 PM (Breakfast, Lunch)
      booking2 = create(:booking, hotel: hotel, adults: 1, children: 0)
      create(:booking_guest, booking: booking2, boat_out_at: Time.utc(2026, 5, 10, 14, 0, 0))

      # Booking 3: Boat-in at 6:00 PM (Dinner)
      booking3 = create(:booking, hotel: hotel, adults: 2, children: 2)
      create(:booking_guest, booking: booking3, boat_in_at: Time.utc(2026, 5, 10, 18, 0, 0))

      # Booking for another hotel (should be excluded)
      booking_other = create(:booking, hotel: other_hotel, adults: 2, children: 0)
      create(:booking_guest, booking: booking_other, boat_in_at: Time.utc(2026, 5, 10, 9, 0, 0))

      # Booking out of date range (should be excluded)
      booking_out_of_range = create(:booking, hotel: hotel, adults: 2, children: 0)
      create(:booking_guest, booking: booking_out_of_range, boat_in_at: Time.utc(2026, 5, 11, 9, 0, 0))

      report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(report.start_date).to eq(start_date)
      expect(report.end_date).to eq(end_date)
      expect(report.records.size).to eq(3)

      # Verify sorting and content
      expect(report.records[0]).to include(
        type: "Boat-in",
        pax: 3,
        meal_type: "Breakfast, Lunch, Dinner"
      )
      expect(report.records[1]).to include(
        type: "Boat-out",
        pax: 1,
        meal_type: "Breakfast, Lunch"
      )
      expect(report.records[2]).to include(
        type: "Boat-in",
        pax: 4,
        meal_type: "Dinner"
      )

      # Total pax = 3 + 1 + 4 = 8
      expect(report.total_pax).to eq(8)
    end

    it "filters by meal_type when provided" do
      # Breakfast, Lunch, Dinner booking (Boat-in 8:00 AM)
      booking1 = create(:booking, hotel: hotel, adults: 2)
      create(:booking_guest, booking: booking1, boat_in_at: Time.utc(2026, 5, 10, 8, 0, 0))

      # Lunch, Dinner booking (Boat-in 1:00 PM)
      booking2 = create(:booking, hotel: hotel, adults: 1)
      create(:booking_guest, booking: booking2, boat_in_at: Time.utc(2026, 5, 10, 13, 0, 0))

      # Dinner booking only (Boat-in 6:00 PM)
      booking3 = create(:booking, hotel: hotel, adults: 4)
      create(:booking_guest, booking: booking3, boat_in_at: Time.utc(2026, 5, 10, 18, 0, 0))

      # Report for Breakfast only (should match only booking 1)
      report_bf = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, meal_type: "Breakfast").call
      expect(report_bf.records.size).to eq(1)
      expect(report_bf.records[0][:confirmation_token]).to eq(booking1.confirmation_token)
      expect(report_bf.total_pax).to eq(2)

      # Report for Lunch (should match booking 1 and booking 2)
      report_lh = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, meal_type: "Lunch").call
      expect(report_lh.records.size).to eq(2)
      expect(report_lh.records.map { |r| r[:confirmation_token] }).to contain_exactly(booking1.confirmation_token, booking2.confirmation_token)
      expect(report_lh.total_pax).to eq(3)

      # Report for Dinner (should match all bookings 1, 2, 3)
      report_dn = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date, meal_type: "Dinner").call
      expect(report_dn.records.size).to eq(3)
      expect(report_dn.total_pax).to eq(7)
    end

    it "opens and closes the window on the property's clock, not the viewer's" do
      island = create(:hotel, time_zone: "Kuala Lumpur")
      booking = create(:booking, hotel: island, adults: 2, children: 0)
      # 20:00 UTC on 9 May is 04:00 on 10 May in Kuala Lumpur -- inside the
      # window for this property, outside it for a viewer reading in UTC.
      create(:booking_guest, booking: booking, boat_in_at: Time.utc(2026, 5, 9, 20, 0, 0))

      counts = [ "UTC", "Hawaii", "Kuala Lumpur" ].map do |zone|
        Time.use_zone(zone) do
          described_class.new(hotel: island, start_date: start_date, end_date: end_date).call.records.size
        end
      end

      expect(counts).to eq([ 1, 1, 1 ])
    end

    it "counts a booking once per transfer even when a second guest carries a boat time" do
      booking = create(:booking, hotel: hotel, adults: 2, children: 1)
      create(:booking_guest, booking: booking, is_primary: true, boat_in_at: Time.utc(2026, 5, 10, 8, 0, 0))
      create(:booking_guest, booking: booking, is_primary: false, boat_in_at: Time.utc(2026, 5, 10, 8, 0, 0))

      report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect(report.records.size).to eq(1)
      expect(report.total_pax).to eq(3)
    end

    it "derives every meal tab from a single pass over the data" do
      booking = create(:booking, hotel: hotel, adults: 2, children: 0)
      create(:booking_guest, booking: booking, boat_in_at: Time.utc(2026, 5, 10, 8, 0, 0))

      report = described_class.new(hotel: hotel, start_date: start_date, end_date: end_date).call

      expect { report.for_meal("lunch") }.not_to change(BookingGuest, :count)
      expect(report.for_meal("lunch").records.size).to eq(1)
      expect(report.for_meal("lunch").records.first[:meal_type]).to eq("Lunch")
      expect(report.pax_for("breakfast")).to eq(2)
      expect(report.pax_for("dinner")).to eq(2)
    end
  end
end
