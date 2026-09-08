require "rails_helper"

RSpec.describe HotelWifiNetwork, type: :model do
  it "requires a password for a protected network" do
    expect(build(:hotel_wifi_network, password: nil)).not_to be_valid
  end

  it "clears the password when the network becomes open" do
    network = create(:hotel_wifi_network)
    network.update!(security_type: "open")

    expect(network.reload.password).to be_nil
  end

  it "encrypts the saved password" do
    network = create(:hotel_wifi_network, password: "private-value")
    ciphertext = described_class.connection.select_value("SELECT password FROM hotel_wifi_networks WHERE id = #{network.id.to_i}")

    expect(ciphertext).not_to eq("private-value")
    expect(network.reload.password).to eq("private-value")
  end

  it "enforces case-insensitive SSID uniqueness within a hotel" do
    network = create(:hotel_wifi_network, ssid: "GuestNet")

    expect(build(:hotel_wifi_network, hotel: network.hotel, ssid: "guestnet")).not_to be_valid
  end
end
