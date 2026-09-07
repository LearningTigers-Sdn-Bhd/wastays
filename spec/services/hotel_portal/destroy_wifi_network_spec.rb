require "rails_helper"

RSpec.describe HotelPortal::DestroyWifiNetwork, type: :service do
  it "promotes another active network after removing the primary network" do
    hotel = create(:hotel)
    primary = create(:hotel_wifi_network, hotel: hotel, primary_network: true, position: 0)
    replacement = create(:hotel_wifi_network, hotel: hotel, position: 1)

    described_class.new(hotel: hotel, network: primary).call

    expect(replacement.reload).to be_primary_network
  end
end
