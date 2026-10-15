require "rails_helper"

RSpec.describe Concierge::StayAccess::Ensure do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }

  it "creates one record for an in-house booking" do
    result = described_class.new(booking: booking).call

    expect(result.success?).to be true
    expect(result.created).to be true
    expect(result.stay_access.hotel).to eq(hotel)
    expect(result.stay_access.booking).to eq(booking)
  end

  it "returns the same record on a second call" do
    first = described_class.new(booking: booking).call
    second = described_class.new(booking: booking).call

    expect(second.stay_access).to eq(first.stay_access)
    expect(second.created).to be false
    expect(booking.concierge_stay_accesses.live.count).to eq(1)
  end

  it "creates a new record after the old one is revoked" do
    first = described_class.new(booking: booking).call.stay_access
    Concierge::StayAccess::Revoke.new(booking: booking).call

    second = described_class.new(booking: booking.reload).call

    expect(second.success?).to be true
    expect(second.stay_access).not_to eq(first)
    expect(second.stay_access.stay_access_id).not_to eq(first.stay_access_id)
  end

  it "refuses a confirmed booking" do
    confirmed = create(:booking, hotel: hotel, status: "confirmed")
    result = described_class.new(booking: confirmed).call

    expect(result.success?).to be false
    expect(confirmed.concierge_stay_accesses).to be_empty
  end
end
