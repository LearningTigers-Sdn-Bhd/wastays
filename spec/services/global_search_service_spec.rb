require "rails_helper"

RSpec.describe GlobalSearchService do
  let(:hotel) { create(:hotel) }
  let!(:booking) { create(:booking, hotel: hotel, guest_name: "Bob", confirmation_token: "WS-BOB01") }

  it "includes page entries" do
    results = described_class.new(hotel, "").perform
    expect(results).to include(hash_including(title: "Hotel Dashboard", group: "Pages"))
  end

  it "finds matching booking" do
    results = described_class.new(hotel, "bob").perform
    expect(results).to include(hash_including(title: a_string_including("WS-BOB01"), group: "Bookings"))
  end
end
