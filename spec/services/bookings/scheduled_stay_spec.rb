# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ScheduledStay do
  let(:hotel) { create(:hotel, time_zone: "Kuala Lumpur") }

  it "uses property policy times for date-only values" do
    create(:property_policy, hotel: hotel, check_in_time: "14:30", check_out_time: "11:15")

    check_in = described_class.at_hotel_time(hotel: hotel, value: Date.new(2026, 6, 12), kind: :check_in)
    check_out = described_class.at_hotel_time(hotel: hotel, value: Date.new(2026, 6, 13), kind: :check_out)

    expect(check_in.in_time_zone(hotel.hotel_time_zone).strftime("%F %H:%M")).to eq("2026-06-12 14:30")
    expect(check_out.in_time_zone(hotel.hotel_time_zone).strftime("%F %H:%M")).to eq("2026-06-13 11:15")
  end

  it "uses fallback times when the hotel has no property policy" do
    check_in = described_class.at_hotel_time(hotel: hotel, value: Date.new(2026, 6, 12), kind: :check_in)
    check_out = described_class.at_hotel_time(hotel: hotel, value: Date.new(2026, 6, 13), kind: :check_out)

    expect(check_in.in_time_zone(hotel.hotel_time_zone).strftime("%H:%M")).to eq("15:00")
    expect(check_out.in_time_zone(hotel.hotel_time_zone).strftime("%H:%M")).to eq("12:00")
  end
end
