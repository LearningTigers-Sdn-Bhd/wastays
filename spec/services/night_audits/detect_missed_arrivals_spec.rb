# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::DetectMissedArrivals do
  it "moves an eligible confirmed arrival into no-show detection" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    business_date = Date.current
    night_audit = create(:night_audit, hotel: hotel, business_date: business_date, status: "running", started_at: Time.current)
    booking = create(:booking, hotel: hotel, status: "confirmed", check_in: business_date, check_out: business_date + 1.day)

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.detected_count).to eq(1)
    expect(booking.reload).to have_attributes(status: "no_show_detected", no_show_detected_business_date: business_date)
  end

  it "uses the hotel-local arrival date when UTC falls on the previous date" do
    hotel = create(:hotel, time_zone: "Kuala Lumpur")
    user = create(:user, account: hotel.account)
    business_date = Date.new(2026, 7, 23)
    zone = hotel.hotel_time_zone
    night_audit = create(:night_audit, hotel: hotel, business_date: business_date, status: "running", started_at: zone.local(2026, 7, 24, 3, 0))
    booking = create(:booking,
      hotel: hotel,
      status: "confirmed",
      check_in: zone.local(2026, 7, 23, 0, 0),
      check_out: zone.local(2026, 7, 24, 0, 0))

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.detected_count).to eq(1)
    expect(booking.reload).to have_attributes(status: "no_show_detected", no_show_detected_business_date: business_date)
  end
end
