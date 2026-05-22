require "rails_helper"

RSpec.describe Concierge::SubmitCheckOutRequest do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", checked_in_at: Time.current) }

  it "creates a CheckOutRequest for a checked-in booking" do
    result = described_class.new(booking: booking).call
    expect(result.success?).to be true
    expect(result.check_out_request).to be_persisted
    expect(result.check_out_request.status).to eq("pending")
  end

  it "fails for a non-checked-in booking" do
    booking.update_column(:status, "confirmed")
    result = described_class.new(booking: booking).call
    expect(result.success?).to be false
  end

  it "prevents duplicate pending requests" do
    described_class.new(booking: booking).call
    result = described_class.new(booking: booking).call
    expect(result.success?).to be false
    expect(result.message).to include("already pending")
  end

  it "stores optional guest notes" do
    result = described_class.new(booking: booking, guest_notes: "Late checkout please").call
    expect(result.check_out_request.guest_notes).to eq("Late checkout please")
  end
end
