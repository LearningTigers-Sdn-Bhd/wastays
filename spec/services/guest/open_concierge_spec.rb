require "rails_helper"

RSpec.describe Guest::OpenConcierge do
  let(:hotel) { create(:hotel, status: "live") }

  it "gives an in-house booking its stay access, open until the stay ends" do
    booking = create(:booking, hotel:, status: "checked_in")

    result = described_class.new(booking:).call

    expect(result.success?).to be true
    expect(result.stay_access).to eq(booking.concierge_stay_accesses.live.first)
    expect(result.expires_at).to eq(Concierge::StayAccess::Eligibility.new(booking:).call.expires_at)
  end

  it "fails for a stay that has not started" do
    booking = create(:booking, hotel:, status: "confirmed", check_in: Date.current + 5.days, check_out: Date.current + 7.days)

    result = described_class.new(booking:).call

    expect(result.success?).to be false
    expect(booking.concierge_stay_accesses).to be_empty
  end
end
