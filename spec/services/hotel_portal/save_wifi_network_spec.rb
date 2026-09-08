require "rails_helper"

RSpec.describe HotelPortal::SaveWifiNetwork, type: :service do
  it "preserves a saved password when an edit submits a blank value" do
    network = create(:hotel_wifi_network, password: "saved-secret")

    result = described_class.new(hotel: network.hotel, network: network, attributes: { label: "Updated", password: "" }).call

    expect(result).to be true
    expect(network.reload.password).to eq("saved-secret")
  end

  it "makes the first active network primary" do
    hotel = create(:hotel)
    network = hotel.hotel_wifi_networks.build

    result = described_class.new(hotel: hotel, network: network, attributes: attributes).call

    expect(result).to be true
    expect(network.reload).to be_primary_network
  end

  def attributes
    { label: "Guests", ssid: "Guests", password: "secret", security_type: "protected", access_scope: "checked_in_guests", active: true }
  end
end
