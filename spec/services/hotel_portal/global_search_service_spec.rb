require "rails_helper"

RSpec.describe HotelPortal::GlobalSearchService do
  let(:hotel) { create(:hotel) }
  let!(:booking) { create(:booking, hotel: hotel, guest_name: "Sam", confirmation_token: "WS-SAM01") }

  it "includes pages for empty query" do
    results = described_class.new(hotel, "").perform
    expect(results).to include(hash_including(title: "Arrival Board", group: "Pages"))
  end

  it "returns booking result for matching query" do
    results = described_class.new(hotel, "sam").perform
    expect(results).to include(hash_including(title: a_string_including("WS-SAM01"), group: "Bookings"))
  end
end
