# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::FrontDesk::DeparturesQuery, frozen_time: Time.zone.local(2026, 7, 15, 12) do
  let(:hotel) { create(:hotel, status: "approved") }

  def hotel_time(date)
    Bookings::ScheduledStay.at_hotel_time(hotel:, value: Date.iso8601(date), kind: :check_out)
  end

  describe "#call" do
    it "returns pending-departure bookings checking out today for current hotel" do
      matching_booking = create(:booking, hotel:, status: "checked_in", check_out: hotel_time("2026-07-15"))
      create(:booking, hotel:, status: "completed", check_out: hotel_time("2026-07-15"))
      create(:booking, hotel:, status: "cancelled", check_out: hotel_time("2026-07-15"))
      create(:booking, hotel:, status: "no_show", check_out: hotel_time("2026-07-15"))
      create(:booking, hotel:, status: "checked_in", check_out: hotel_time("2026-07-16"))
      create(:booking, hotel: create(:hotel, status: "approved"), status: "checked_in", check_out: hotel_time("2026-07-15"))

      query = described_class.new(hotel:, params: {})

      expect(query.call).to contain_exactly(matching_booking)
    end

    %w[confirmed no_show_detected checked_in checkout_required].each do |status|
      it "includes #{status} bookings checking out today" do
        extra_attrs = status == "no_show_detected" ? { no_show_detected_business_date: Date.new(2026, 7, 15) } : {}
        matching_booking = create(:booking, hotel:, status:, check_out: hotel_time("2026-07-15"), **extra_attrs)

        query = described_class.new(hotel:, params: {})

        expect(query.call).to contain_exactly(matching_booking)
      end
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
          status: "checked_in",
          check_out: hotel_time("2026-07-15"),
          field => "A%_B"
        )
        create(
          :booking,
          hotel:,
          status: "checked_in",
          check_out: hotel_time("2026-07-15"),
          field => "AxxB"
        )

        query = described_class.new(hotel:, params: { departure_query: "A%_B" })

        expect(query.call).to contain_exactly(matching_booking)
      end
    end

    it "orders by scheduled checkout date then creation time" do
      later_checkout = create(:booking, hotel:, status: "checked_in", check_out: hotel_time("2026-07-16"), created_at: 1.hour.ago)
      earlier_checkout = create(:booking, hotel:, status: "checked_in", check_out: hotel_time("2026-07-15"), created_at: 2.hours.ago)

      query = described_class.new(hotel:, params: { departure_end_date: "2026-07-16" })

      expect(query.call).to eq([ earlier_checkout, later_checkout ])
    end
  end

  it "prefers scoped dates over legacy dates" do
    legacy_booking = create(:booking, hotel:, status: "checked_in", check_out: hotel_time("2026-07-15"))
    scoped_booking = create(:booking, hotel:, status: "checked_in", check_out: hotel_time("2026-07-16"))

    query = described_class.new(hotel:, params: { start_date: "2026-07-15", departure_start_date: "2026-07-16" })

    expect(query.call).to contain_exactly(scoped_booking)
    expect(query.call).not_to include(legacy_booking)
  end

  it "uses the hotel-local day for invalid and missing dates", frozen_time: Time.utc(2026, 7, 15, 18, 30) do
    hotel.update!(time_zone: "Kuala Lumpur")
    invalid = described_class.new(hotel:, params: { departure_start_date: "not-a-date" })
    missing = described_class.new(hotel:, params: {})

    expect([ invalid.start_date, invalid.end_date ]).to eq([ Date.new(2026, 7, 16) ] * 2)
    expect([ missing.start_date, missing.end_date ]).to eq([ Date.new(2026, 7, 16) ] * 2)
  end

  describe "#total_count" do
    it "keeps count unfiltered" do
      create(:booking, hotel:, status: "checked_in", check_out: hotel_time("2026-07-15"), guest_name: "Aisha")
      create(:booking, hotel:, status: "checked_in", check_out: hotel_time("2026-07-15"), guest_name: "Noor")

      query = described_class.new(hotel:, params: { departure_query: "Aisha" })

      expect(query.total_count).to eq(2)
    end
  end
end
