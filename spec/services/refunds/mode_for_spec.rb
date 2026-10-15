require "rails_helper"

RSpec.describe Refunds::ModeFor do
  let(:policy) { create(:refund_policy, min_days_before_checkin: 3, refund_percentage: 80.0) }

  def mode_for(booking) = described_class.new(booking:, policy:).call

  it "is pre-stay for a confirmed booking inside the policy window" do
    expect(mode_for(create(:booking, status: "confirmed", check_in: Date.current + 10.days, check_out: Date.current + 12.days))).to eq(:pre_stay)
  end

  it "is pre-stay for a cancelled booking whose request was rejected" do
    booking = create(:booking, status: "cancelled", check_in: Date.current + 10.days, check_out: Date.current + 12.days)
    create(:refund_request, booking:, status: "rejected")

    expect(mode_for(booking)).to eq(:pre_stay)
  end

  it "is post-stay for a guest in house with no request" do
    expect(mode_for(create(:booking, status: "checked_in"))).to eq(:post_stay)
  end

  it "is nothing for a guest in house with an open request" do
    booking = create(:booking, status: "checked_in")
    create(:refund_request, booking:, status: "pending")

    expect(mode_for(booking)).to be_nil
  end

  it "is nothing for a confirmed booking too close to check-in" do
    expect(mode_for(create(:booking, status: "confirmed", check_in: Date.current + 1.day, check_out: Date.current + 2.days))).to be_nil
  end
end
