# frozen_string_literal: true

require "rails_helper"

RSpec.describe NightAudits::ReviewMissedArrivals do
  it "moves an eligible confirmed arrival into no-show review" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    business_date = Date.current
    night_audit = create(:night_audit, hotel: hotel, business_date: business_date, status: "running", started_at: Time.current)
    booking = create(:booking, hotel: hotel, status: "confirmed", check_in: business_date, check_out: business_date + 1.day)

    result = described_class.call(night_audit: night_audit, user: user)

    expect(result.reviewed_count).to eq(1)
    expect(booking.reload).to have_attributes(status: "review_no_show", no_show_review_business_date: business_date)
  end
end
