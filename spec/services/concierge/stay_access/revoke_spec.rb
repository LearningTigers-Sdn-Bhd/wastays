require "rails_helper"

RSpec.describe Concierge::StayAccess::Revoke do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in") }

  it "revokes the live record" do
    record = create(:concierge_stay_access, hotel: hotel, booking: booking)
    result = described_class.new(booking: booking).call

    expect(result.success?).to be true
    expect(result.revoked_count).to eq(1)
    expect(record.reload.revoked?).to be true
  end

  it "keeps the record and its id after revocation" do
    record = create(:concierge_stay_access, hotel: hotel, booking: booking)
    original_id = record.stay_access_id

    described_class.new(booking: booking).call

    expect(record.reload.stay_access_id).to eq(original_id)
  end

  it "does nothing when no live record exists" do
    result = described_class.new(booking: booking).call

    expect(result.success?).to be true
    expect(result.revoked_count).to eq(0)
  end

  it "refuses a missing booking" do
    expect(described_class.new(booking: nil).call.success?).to be false
  end
end
