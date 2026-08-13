require "rails_helper"

RSpec.describe Onboarding::SubmissionSnapshot do
  let(:hotel) { create(:hotel) }

  it "records OTA credential presence without secrets" do
    create(:hotel_ota_credential, hotel:, channel_name: "Booking.com", username: "private-user", password: "private-password")

    result = described_class.call(hotel:)
    serialized = result.data.to_json

    expect(result.data.fetch("ota_handover")).to eq([
      { "channel_name" => "Booking.com", "credentials_supplied" => true }
    ])
    expect(serialized).not_to include("private-user", "private-password", "username", "password")
    expect(result.digest).to eq(described_class.call(hotel:).digest)
  end
end
