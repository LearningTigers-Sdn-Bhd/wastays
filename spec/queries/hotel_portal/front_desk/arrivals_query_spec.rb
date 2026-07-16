# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::FrontDesk::ArrivalsQuery do
  let(:hotel) { create(:hotel, status: "approved") }

  around do |example|
    travel_to(Date.new(2026, 7, 15)) { example.run }
  end

  describe "#call" do
    it "scopes active bookings to selected hotel and arrival date" do
      matching_booking = create(:booking, hotel:, status: "confirmed", check_in: hotel_time("2026-07-15"))
      create(:booking, hotel:, status: "completed", check_in: hotel_time("2026-07-15"))
      create(:booking, hotel:, status: "confirmed", check_in: hotel_time("2026-07-16"))
      create(:booking, hotel: create(:hotel, status: "approved"), status: "confirmed", check_in: hotel_time("2026-07-15"))

      query = described_class.new(hotel:, params: { arrival_date: "2026-07-15" })

      expect(query.call).to contain_exactly(matching_booking)
    end

    {
      guest_name: "guest name",
      guest_email: "guest email",
      guest_phone: "guest phone",
      confirmation_token: "confirmation reference"
    }.each do |field, description|
      it "searches literal percent and underscore in #{description}" do
        matching_booking = create(
          :booking,
          hotel:,
          status: "confirmed",
          check_in: hotel_time("2026-07-15"),
          field => "A%_B"
        )
        create(
          :booking,
          hotel:,
          status: "confirmed",
          check_in: hotel_time("2026-07-15"),
          field => "AxxB"
        )

        query = described_class.new(hotel:, params: { arrival_date: "2026-07-15", arrival_q: "A%_B" })

        expect(query.call).to contain_exactly(matching_booking)
      end
    end

    it "orders matching bookings by creation time ascending" do
      later_booking = create(:booking, hotel:, status: "confirmed", check_in: hotel_time("2026-07-15"), created_at: 1.hour.from_now)
      earlier_booking = create(:booking, hotel:, status: "confirmed", check_in: hotel_time("2026-07-15"), created_at: 1.hour.ago)

      query = described_class.new(hotel:, params: { arrival_date: "2026-07-15" })

      expect(query.call).to eq([ earlier_booking, later_booking ])
    end

    it "orders equal creation times by id ascending for stable pagination" do
      timestamp = Time.zone.local(2026, 7, 15, 9, 0)
      bookings = 27.times.map do |index|
        create(
          :booking,
          hotel:,
          status: "confirmed",
          confirmation_token: format("ARRIVAL-TIE-%02d", index),
          check_in: hotel_time("2026-07-15"),
          created_at: timestamp
        )
      end

      query = described_class.new(hotel:, params: { arrival_date: "2026-07-15" })

      expect(query.call.to_sql).to match(/ORDER BY "bookings"\."created_at" ASC, "bookings"\."id" ASC/)
      expect(query.call.page(1).per(25).pluck(:id)).to eq(bookings.first(25).map(&:id))
      expect(query.call.page(2).per(25).pluck(:id)).to eq(bookings.last(2).map(&:id))
    end
  end

  describe "#start_date" do
    it "uses valid selected arrival date" do
      query = described_class.new(hotel:, params: { arrival_date: "2026-07-15" })

      expect(query.start_date).to eq(Date.new(2026, 7, 15))
    end

    it "falls back to today for invalid arrival date" do
      query = described_class.new(hotel:, params: { arrival_date: "not-a-date" })

      expect(query.start_date).to eq(Date.today)
    end
  end

  describe "counts" do
    it "keeps selected range count unfiltered" do
      create(:booking, hotel:, status: "confirmed", check_in: hotel_time("2026-07-15"), guest_name: "Aisha")
      create(:booking, hotel:, status: "confirmed", check_in: hotel_time("2026-07-15"), guest_name: "Noor")
      create(:booking, hotel:, status: "confirmed", check_in: hotel_time("2026-07-16"))

      query = described_class.new(hotel:, params: { arrival_date: "2026-07-15", arrival_q: "Aisha" })

      expect(query.total_count).to eq(2)
    end
  end

  def hotel_time(date)
    Bookings::ScheduledStay.at_hotel_time(hotel:, value: Date.iso8601(date), kind: :check_in)
  end
end
