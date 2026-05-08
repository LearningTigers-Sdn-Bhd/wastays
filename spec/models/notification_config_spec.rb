require "rails_helper"

RSpec.describe NotificationConfig, type: :model do
  it "validates supported notification types and channels" do
    config = described_class.new(
      hotel: create(:hotel),
      notification_type: "check_in_confirmation",
      enabled: true,
      channels: [ "whatsapp", "email" ],
      settings: {}
    )

    expect(config).to be_valid
  end

  it "supports whatsapp-first defaults" do
    config = described_class.new(
      hotel: create(:hotel),
      notification_type: "check_in_confirmation",
      enabled: true,
      channels: [ "whatsapp" ],
      settings: {}
    )

    expect(config).to be_valid
  end

  it "rejects unsupported channels" do
    config = described_class.new(
      hotel: create(:hotel),
      notification_type: "check_in_confirmation",
      enabled: true,
      channels: [ "sms" ],
      settings: {}
    )

    expect(config).not_to be_valid
    expect(config.errors[:channels]).to include("contains unsupported values")
  end
end
