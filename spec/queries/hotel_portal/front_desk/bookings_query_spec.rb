# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::FrontDesk::BookingsQuery do
  let(:hotel) { create(:hotel, status: "approved") }

  describe "#call" do
    it "returns all hotel bookings when no date range is selected" do
      older_booking = create(:booking, hotel:, check_in: hotel_time("2026-07-14"))
      newer_booking = create(:booking, hotel:, check_in: hotel_time("2026-07-16"))
      create(:booking, hotel: create(:hotel, status: "approved"), check_in: hotel_time("2026-07-15"))

      expect(described_class.new(hotel:, params: {}).call).to contain_exactly(older_booking, newer_booking)
      expect(described_class.new(hotel:, params: {}).start_date).to be_nil
    end

    it "uses an end-only date as a single-day filter" do
      matching_booking = create(:booking, hotel:, check_in: hotel_time("2026-07-15"))
      create(:booking, hotel:, check_in: hotel_time("2026-07-16"))

      query = described_class.new(hotel:, params: { booking_end_date: "2026-07-15" })

      expect(query.call).to contain_exactly(matching_booking)
    end

    it "normalizes reversed date ranges" do
      matching_booking = create(:booking, hotel:, check_in: hotel_time("2026-07-15"))

      query = described_class.new(hotel:, params: { booking_start_date: "2026-07-16", booking_end_date: "2026-07-14" })

      expect(query.start_date).to eq(Date.new(2026, 7, 14))
      expect(query.end_date).to eq(Date.new(2026, 7, 16))
      expect(query.call).to include(matching_booking)
    end

    it "prefers scoped dates over legacy dates" do
      legacy_booking = create(:booking, hotel:, check_in: hotel_time("2026-07-15"))
      scoped_booking = create(:booking, hotel:, check_in: hotel_time("2026-07-16"))

      query = described_class.new(hotel:, params: { start_date: "2026-07-15", booking_start_date: "2026-07-16" })

      expect(query.call).to contain_exactly(scoped_booking)
      expect(query.call).not_to include(legacy_booking)
    end


    it "uses the hotel-local day for an invalid supplied date" do
      hotel.update!(time_zone: "Kuala Lumpur")

      travel_to(Time.utc(2026, 7, 15, 18, 30)) do
        query = described_class.new(hotel:, params: { booking_start_date: "not-a-date" })

        expect([ query.start_date, query.end_date ]).to eq([ Date.new(2026, 7, 16) ] * 2)
      end
    end
  end

  def hotel_time(date)
    Bookings::ScheduledStay.at_hotel_time(hotel:, value: Date.iso8601(date), kind: :check_in)
  end
end
