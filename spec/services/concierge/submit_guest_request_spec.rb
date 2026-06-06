require "rails_helper"

RSpec.describe Concierge::SubmitGuestRequest do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", checked_in_at: Time.current) }

  it "creates a housekeeping request" do
    result = described_class.new(booking: booking, kind: "housekeeping", details: "Extra towels").call
    expect(result.success?).to be true
    expect(result.request).to be_a(HousekeepingRequest)
  end

  it "creates a complaint request" do
    result = described_class.new(booking: booking, kind: "complaint", details: "AC broken").call
    expect(result.success?).to be true
    expect(result.request).to be_a(ComplaintRequest)
  end

  it "tags the request with concierge_page source" do
    result = described_class.new(booking: booking, kind: "housekeeping", details: "Towels").call
    expect(result.request.metadata["source"]).to eq("concierge_page")
  end

  it "fails for blank details" do
    result = described_class.new(booking: booking, kind: "housekeeping", details: "").call
    expect(result.success?).to be false
  end

  it "fails for invalid kind" do
    result = described_class.new(booking: booking, kind: "unknown", details: "test").call
    expect(result.success?).to be false
  end

  it "fails for cancelled bookings" do
    cancelled = create(:booking, hotel: hotel, status: "cancelled")
    result = described_class.new(booking: cancelled, kind: "housekeeping", details: "test").call
    expect(result.success?).to be false
  end
end
