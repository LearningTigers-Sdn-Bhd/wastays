require "rails_helper"

RSpec.describe Concierge::StayAccess::Eligibility do
  let(:hotel) { create(:hotel, status: "live") }

  def call(booking, now: Time.current)
    described_class.new(booking: booking, now: now).call
  end

  it "gives full access to every in-house status" do
    Booking::IN_HOUSE_STATUSES.each do |status|
      booking = create(:booking, hotel: hotel, status: status)
      result = call(booking)

      expect(result.success?).to be(true), "expected #{status} to hold a stay page"
      expect(result.level).to eq(:full)
    end
  end

  it "refuses a confirmed booking" do
    booking = create(:booking, hotel: hotel, status: "confirmed")

    expect(call(booking).success?).to be false
  end

  it "gives grace access inside seven days of the check-out time" do
    checked_out = Time.current - 2.days
    booking = create(:booking, hotel: hotel, status: "completed", checked_out_at: checked_out)
    result = call(booking)

    expect(result.success?).to be true
    expect(result.level).to eq(:grace)
    expect(result.expires_at).to be_within(1.second).of(checked_out + 7.days)
  end

  it "refuses a completed booking after the grace period" do
    booking = create(:booking, hotel: hotel, status: "completed", checked_out_at: 8.days.ago)

    expect(call(booking).success?).to be false
  end

  it "counts the grace period from the planned departure when no check-out time exists" do
    booking = create(:booking, hotel: hotel, status: "completed", checked_out_at: nil)
    result = call(booking)

    expect(result.expires_at).to be_within(1.second).of(booking.check_out + 7.days)
  end

  it "refuses a missing booking" do
    expect(call(nil).success?).to be false
  end

  it "gives one generic message on every refusal" do
    booking = create(:booking, hotel: hotel, status: "confirmed")

    expect(call(booking).error).to eq(call(nil).error)
  end
end
