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

  it "routes reservation pages and quick actions to front desk tabs" do
    routes = Rails.application.routes.url_helpers
    service = described_class.new(hotel, "")

    expect(service.perform).to include(
      hash_including(title: "Bookings", url: routes.hotel_front_desk_path(hotel, tab: "bookings")),
      hash_including(title: "Arrival Board", url: routes.hotel_front_desk_path(hotel, tab: "arrivals")),
      hash_including(title: "In-House Guests", url: routes.hotel_front_desk_path(hotel, tab: "in_house"))
    )
    expect(service.quick_actions).to include(
      hash_including(label: "Go to bookings", url: routes.hotel_front_desk_path(hotel, tab: "bookings")),
      hash_including(label: "Go to arrival board", url: routes.hotel_front_desk_path(hotel, tab: "arrivals"))
    )
  end
end
