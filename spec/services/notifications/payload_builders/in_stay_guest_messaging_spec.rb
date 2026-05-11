require "rails_helper"

RSpec.describe Notifications::PayloadBuilders::InStayGuestMessaging do
  let(:hotel) { create(:hotel, name: "Sample Hotel") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_name: "Test Guest",
      guest_email: "test@example.com",
      guest_phone: "0123456789",
      check_in: Date.new(2026, 5, 10),
      check_out: Date.new(2026, 5, 12))
  end

  it "builds mid_stay payload with booking context" do
    payload = described_class.new(
      booking: booking,
      rule_key: "mid_stay",
      scheduled_for: Time.zone.local(2026, 5, 11, 12, 0)
    ).call

    expect(payload[:notification_type]).to eq("in_stay_guest_messaging")
    expect(payload[:rule_key]).to eq("mid_stay")
    expect(payload[:rule_label]).to eq("Mid-stay check-in")
    expect(payload[:hotel_name]).to eq("Sample Hotel")
    expect(payload[:guest_email]).to eq("test@example.com")
    expect(payload[:message_headline]).to eq("How is everything so far?")
    expect(payload[:message_body]).to include("front desk")
    expect(payload[:message_suggestion]).to include("Current stay:")
  end

  it "builds distinct content per rule" do
    upsell_payload = described_class.new(
      booking: booking,
      rule_key: "upsell",
      scheduled_for: Time.zone.local(2026, 5, 10, 17, 0)
    ).call
    activity_payload = described_class.new(
      booking: booking,
      rule_key: "activity",
      scheduled_for: Time.zone.local(2026, 5, 11, 10, 0)
    ).call

    expect(upsell_payload[:message_headline]).to include("enjoyable")
    expect(activity_payload[:message_headline]).to include("final day")
    expect(upsell_payload[:message_body]).not_to eq(activity_payload[:message_body])
  end

  it "raises on unsupported rule" do
    expect {
      described_class.new(
        booking: booking,
        rule_key: "unknown",
        scheduled_for: Time.current
      ).call
    }.to raise_error(ArgumentError, /Unsupported in-stay rule/)
  end
end
