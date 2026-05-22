require "rails_helper"

RSpec.describe Concierge::BookingLookup do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Ahmad Zulkifli", status: "confirmed") }

  def lookup(token: booking.confirmation_token, ip: "1.2.3.4")
    described_class.new(hotel: hotel, confirmation_token: token, request_ip: ip).call
  end

  it "succeeds with correct token" do
    result = lookup
    expect(result.success?).to be true
    expect(result.booking).to eq(booking)
  end

  it "normalises the confirmation token to uppercase" do
    result = lookup(token: booking.confirmation_token.downcase)
    expect(result.success?).to be true
  end

  it "returns :not_found for unknown token" do
    result = lookup(token: "WS-XXXXXXXX")
    expect(result.success?).to be false
    expect(result.error_code).to eq(:not_found)
  end
end
