# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::PayloadBuilders::PreArrivalNotification do
  let(:booking) { create(:booking, check_in: Date.new(2026, 5, 15), check_out: Date.new(2026, 5, 16)) }

  it "builds payload for d2 stage" do
    scheduled_for = Time.zone.local(2026, 5, 13, 0, 0)

    payload = described_class.new(booking: booking, stage: "d2", scheduled_for: scheduled_for).call

    expect(payload[:notification_type]).to eq("pre_arrival_notification")
    expect(payload[:stage]).to eq("d2")
    expect(payload[:scheduled_for]).to eq(scheduled_for.iso8601)
    expect(payload[:booking_id]).to eq(booking.id)
  end

  it "builds payload for d1 stage" do
    scheduled_for = Time.zone.local(2026, 5, 14, 0, 0)

    payload = described_class.new(booking: booking, stage: "d1", scheduled_for: scheduled_for).call

    expect(payload[:stage]).to eq("d1")
    expect(payload[:guest_name]).to eq(booking.guest_name)
    expect(payload[:hotel_name]).to eq(booking.hotel.name)
  end

  it "raises for unsupported stage" do
    expect {
      described_class.new(booking: booking, stage: "d3", scheduled_for: Time.current).call
    }.to raise_error(ArgumentError, "Unsupported pre-arrival stage: d3")
  end
end
