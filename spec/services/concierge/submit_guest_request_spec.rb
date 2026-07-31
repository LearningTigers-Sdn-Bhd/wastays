require "rails_helper"

RSpec.describe Concierge::SubmitGuestRequest do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", checked_in_at: Time.current) }

  it "creates a housekeeping request" do
    result = described_class.new(booking: booking, kind: "housekeeping", details: "Extra towels").call
    expect(result.success?).to be true
    expect(result.request).to be_a(HousekeepingRequest)
    expect(result.request.work_context).to eq("guest_request")
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

  it "accepts housekeeping requests before arrival" do
    pre_arrival = [
      create(:booking, hotel: hotel, status: "confirmed"),
      create(:booking, hotel: hotel, status: "review_no_show", no_show_review_business_date: Date.current)
    ]

    pre_arrival.each do |booking|
      result = described_class.new(booking: booking, kind: "housekeeping", details: "test").call

      expect(result.success?).to be(true), "expected #{booking.status} to accept a request"
      expect(result.request.work_context).to eq("guest_request")
    end
  end

  it "fails once the stay is over" do
    departed = create(:booking, hotel: hotel, status: "completed")

    result = described_class.new(booking: departed, kind: "housekeeping", details: "test").call

    expect(result.success?).to be false
  end
end
