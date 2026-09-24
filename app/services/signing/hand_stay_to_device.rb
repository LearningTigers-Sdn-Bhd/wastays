# frozen_string_literal: true

module Signing
  # Tells a parked tablet where to go next.
  #
  # What travels is an instruction to navigate, not the card itself. The tablet
  # ends up on the very page a guest would open from their own phone, so there
  # is one signing surface to build and to test rather than two that must agree.
  #
  # Only a path crosses the wire. The card's token is not in it — the tablet
  # asks for that in its own request — so anything that could overhear this
  # stream learns which tablet is busy and nothing about the guest.
  class HandStayToDevice
    include Rails.application.routes.url_helpers

    def self.call(device:) = new(device: device).call

    # Sends a tablet back to its idle screen: the stay is pulled out of its
    # hands, so the desk can take a guest who has walked away off the display.
    def self.release(device:) = new(device: device).release

    def initialize(device:)
      @device = device
    end

    def call
      broadcast(next_signing_device_path(@device.public_token))
    end

    def release
      @device.release!
      broadcast(signing_device_path(@device.public_token))
    end

    private

    def broadcast(url)
      Turbo::StreamsChannel.broadcast_replace_to(
        [ @device, :signing ],
        target: SigningDevice::COMMAND_REGION_ID,
        partial: "public/signing_devices/command",
        locals: { url: url }
      )
    end
  end
end
