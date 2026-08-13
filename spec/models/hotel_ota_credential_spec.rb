# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelOtaCredential do
  let(:hotel) { create(:hotel) }

  it "encrypts the login rather than storing what was typed" do
    credential = create(:hotel_ota_credential, hotel: hotel, username: "acme-hotel", password: "extranet-secret")

    raw = described_class.connection.select_one(
      "SELECT username, password FROM hotel_ota_credentials WHERE id = #{credential.id}"
    )

    expect(raw["username"]).not_to include("acme-hotel")
    expect(raw["password"]).not_to include("extranet-secret")
    expect(credential.reload).to have_attributes(username: "acme-hotel", password: "extranet-secret")
  end

  it "holds one row per channel for a property, however it was capitalised" do
    create(:hotel_ota_credential, hotel: hotel, channel_name: "Booking.com")

    duplicate = build(:hotel_ota_credential, hotel: hotel, channel_name: "booking.COM")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:channel_name]).to include("already has credentials for this property")
  end

  it "lets another property keep its own row for the same channel" do
    create(:hotel_ota_credential, hotel: hotel, channel_name: "Booking.com")

    expect(build(:hotel_ota_credential, hotel: create(:hotel), channel_name: "Booking.com")).to be_valid
  end

  it "requires a channel to sign in to" do
    expect(build(:hotel_ota_credential, hotel: hotel, channel_name: " ")).not_to be_valid
  end

  it "tidies what was typed and starts out waiting to be processed" do
    credential = create(:hotel_ota_credential, hotel: hotel, channel_name: " Agoda ",
                                               market_manager_email: " Dana@Agoda.com ")

    expect(credential).to have_attributes(
      channel_name: "Agoda", market_manager_email: "dana@agoda.com", status: "pending"
    )
    expect(credential).not_to be_processed
  end

  it "rejects a market manager address that is not one" do
    expect(build(:hotel_ota_credential, hotel: hotel, market_manager_email: "dana(at)agoda")).not_to be_valid
  end
end
