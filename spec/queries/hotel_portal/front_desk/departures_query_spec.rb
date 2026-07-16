# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::FrontDesk::DeparturesQuery do
  let(:hotel) { create(:hotel, status: "approved") }

  around do |example|
    time = example.metadata[:hotel_midnight] ? Time.utc(2026, 7, 15, 18, 30) : Time.zone.local(2026, 7, 15, 12)
    travel_to(time) { example.run }
  end

  def hotel_time(date)
    Bookings::ScheduledStay.at_hotel_time(hotel:, value: Date.iso8601(date), kind: :check_out)
  end

  describe "#call" do
    it "returns only completed bookings checked out today for current hotel" do
      matching_booking = create(:booking, hotel:, status: "completed", checked_out_at: 1.hour.ago)
      create(:booking, hotel:, status: "checked_in", checked_out_at: 1.hour.ago)
      create(:booking, hotel:, status: "completed", checked_out_at: 1.day.ago)
      create(:booking, hotel: create(:hotel, status: "approved"), status: "completed", checked_out_at: 1.hour.ago)

      query = described_class.new(hotel:, params: {})

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
          status: "completed",
          checked_out_at: 1.hour.ago,
          field => "A%_B"
        )
        create(
          :booking,
          hotel:,
          status: "completed",
          checked_out_at: 1.hour.ago,
          field => "AxxB"
        )

        query = described_class.new(hotel:, params: { departure_query: "A%_B" })

        expect(query.call).to contain_exactly(matching_booking)
      end
    end

    it "orders by checkout time then creation time descending" do
      earlier_booking = create(:booking, hotel:, status: "completed", checked_out_at: 2.hours.ago, created_at: 3.hours.ago)
      latest_booking = create(:booking, hotel:, status: "completed", checked_out_at: 1.hour.ago, created_at: 2.hours.ago)

      query = described_class.new(hotel:, params: {})

      expect(query.call).to eq([ latest_booking, earlier_booking ])
    end

    it "uses creation time descending when checkout times match" do
      checked_out_at = 1.hour.ago
      earlier_booking = create(:booking, hotel:, status: "completed", checked_out_at:, created_at: 3.hours.ago)
      later_booking = create(:booking, hotel:, status: "completed", checked_out_at:, created_at: 2.hours.ago)

      query = described_class.new(hotel:, params: {})

      expect(query.call).to eq([ later_booking, earlier_booking ])
    end
  end

  it "prefers scoped dates over legacy dates" do
    legacy_booking = create(:booking, hotel:, status: "completed", checked_out_at: hotel_time("2026-07-15"))
    scoped_booking = create(:booking, hotel:, status: "completed", checked_out_at: hotel_time("2026-07-16"))

    query = described_class.new(hotel:, params: { start_date: "2026-07-15", departure_start_date: "2026-07-16" })

    expect(query.call).to contain_exactly(scoped_booking)
    expect(query.call).not_to include(legacy_booking)
  end


  it "uses the hotel-local day for invalid and missing dates", :hotel_midnight do
    hotel.update!(time_zone: "Kuala Lumpur")
    invalid = described_class.new(hotel:, params: { departure_start_date: "not-a-date" })
    missing = described_class.new(hotel:, params: {})

    expect([ invalid.start_date, invalid.end_date ]).to eq([ Date.new(2026, 7, 16) ] * 2)
    expect([ missing.start_date, missing.end_date ]).to eq([ Date.new(2026, 7, 16) ] * 2)
  end

  describe "#total_count" do
    it "keeps count unfiltered" do
      create(:booking, hotel:, status: "completed", checked_out_at: 2.hours.ago, guest_name: "Aisha")
      create(:booking, hotel:, status: "completed", checked_out_at: 1.hour.ago, guest_name: "Noor")

      query = described_class.new(hotel:, params: { departure_query: "Aisha" })

      expect(query.total_count).to eq(2)
    end
  end
end
