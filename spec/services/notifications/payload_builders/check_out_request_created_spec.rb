require "rails_helper"

RSpec.describe Notifications::PayloadBuilders::CheckOutRequestCreated do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", checked_in_at: Time.current) }
  let(:request) { create(:check_out_request, booking: booking, guest_notes: "Late checkout") }

  it "returns the expected payload keys" do
    payload = described_class.new(check_out_request: request).call
    expect(payload[:notification_type]).to eq("check_out_request_created")
    expect(payload[:guest_notes]).to eq("Late checkout")
    expect(payload[:confirmation_token]).to eq(booking.confirmation_token)
  end
end
