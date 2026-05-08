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

  it "accepts post-stay review request type" do
    config = described_class.new(
      hotel: create(:hotel),
      notification_type: "post_stay_review_request",
      enabled: true,
      channels: [ "whatsapp" ],
      settings: { review_link: "https://g.page/r/example/review", send_delay_hours: 2 }
    )

    expect(config).to be_valid
  end

  it "accepts check-out receipt message type" do
    config = described_class.new(
      hotel: create(:hotel),
      notification_type: "check_out_receipt_message",
      enabled: true,
      channels: [ "whatsapp", "email" ],
      settings: {}
    )

    expect(config).to be_valid
  end

  it "accepts pre-arrival notification with d2 and d1 stages" do
    config = described_class.new(
      hotel: create(:hotel),
      notification_type: "pre_arrival_notification",
      enabled: true,
      channels: [ "whatsapp", "email" ],
      settings: { stages: %w[d2 d1] }
    )

    expect(config).to be_valid
  end

  it "rejects unsupported pre-arrival stages" do
    config = described_class.new(
      hotel: create(:hotel),
      notification_type: "pre_arrival_notification",
      enabled: true,
      channels: [ "whatsapp", "email" ],
      settings: { stages: %w[d3] }
    )

    expect(config).not_to be_valid
    expect(config.errors[:settings]).to include("contains unsupported pre-arrival stages")
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
