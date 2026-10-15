# frozen_string_literal: true

require "rails_helper"

RSpec.describe Signing::HandStayToDevice do
  let(:hotel) { create(:hotel, status: "live") }
  let(:device) { hotel.signing_devices.create!(label: "Lobby tablet") }
  let(:booking) { create(:booking, hotel: hotel) }

  describe ".call" do
    it "broadcasts the device to the next-card hop, without the card's own token" do
      device.hand_stay(booking)

      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        [ device, :signing ],
        target: SigningDevice::COMMAND_REGION_ID,
        partial: "public/signing_devices/command",
        locals: { url: Rails.application.routes.url_helpers.next_signing_device_path(device.public_token) }
      )

      described_class.call(device: device)
    end
  end

  describe ".release" do
    it "clears the device's stay and broadcasts it back to the idle screen" do
      device.hand_stay(booking)

      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).with(
        [ device, :signing ],
        target: SigningDevice::COMMAND_REGION_ID,
        partial: "public/signing_devices/command",
        locals: { url: Rails.application.routes.url_helpers.signing_device_path(device.public_token) }
      )

      expect {
        described_class.release(device: device)
      }.to change { device.reload.current_booking_id }.from(booking.id).to(nil)
    end
  end
end
