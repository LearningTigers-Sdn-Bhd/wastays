require "rails_helper"

RSpec.describe Notifications::PayloadBuilders::ConciergeRequestCreated do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", checked_in_at: Time.current) }
  let(:hk_request) { create(:housekeeping_request, booking: booking, request_details: "Extra towels") }

  it "returns the expected payload for a housekeeping request" do
    payload = described_class.new(request: hk_request, kind: "housekeeping").call
    expect(payload[:notification_type]).to eq("concierge_request_created")
    expect(payload[:request_kind]).to eq("housekeeping")
    expect(payload[:request_details]).to eq("Extra towels")
  end
end
