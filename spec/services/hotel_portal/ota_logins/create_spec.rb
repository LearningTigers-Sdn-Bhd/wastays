# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::OtaLogins::Create do
  let(:hotel) { create(:hotel) }

  it "adds a pending login without changing onboarding progress" do
    sections = hotel.onboarding_sections.map(&:attributes)
    hotel_attributes = hotel.attributes

    result = described_class.call(hotel: hotel, attributes: { channel_name: " Agoda ", username: "ota-user", password: "private-password" })

    expect(result).to be_success
    expect(result.credential.reload).to have_attributes(channel_name: "Agoda", status: "pending", username: "ota-user", password: "private-password")
    expect(hotel.reload.attributes).to eq(hotel_attributes)
    expect(hotel.onboarding_sections.reload.map(&:attributes)).to eq(sections)
  end

  it "returns validation errors without saving" do
    result = described_class.call(hotel: hotel, attributes: { channel_name: " " })

    expect(result).not_to be_success
    expect(result.credential.errors[:channel_name]).to be_present
  end

  it "returns a channel error when concurrent creation hits the unique constraint" do
    credential = hotel.hotel_ota_credentials.build(channel_name: "Agoda")
    allow(hotel.hotel_ota_credentials).to receive(:build).and_return(credential)
    allow(credential).to receive(:save).and_raise(ActiveRecord::RecordNotUnique)

    result = described_class.call(hotel: hotel, attributes: { channel_name: "Agoda" })

    expect(result).not_to be_success
    expect(result.credential.errors[:channel_name]).to include("already has credentials for this property")
  end
end
