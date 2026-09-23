# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::SigningDevices", type: :request do
  let(:hotel) { create(:hotel, status: "live", grc_tablet_signing_enabled: true) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Aisha Tan") }
  let(:device) { hotel.signing_devices.create!(label: "Lobby tablet") }

  describe "GET /signing-device/:token" do
    it "hides the site chrome, since nothing else belongs on a kiosk" do
      get signing_device_path(device.public_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Login")
    end
  end

  describe "POST /signing-device/:token/release" do
    it "clears whatever stay the tablet was holding, without touching signatures" do
      device.hand_stay(booking)

      post release_signing_device_path(device.public_token)

      expect(device.reload.current_booking).to be_nil
      expect(response).to redirect_to(signing_device_path(device.public_token))
    end

    it "lets a tablet mid-signing back out of the wrong stay from the card page" do
      device.hand_stay(booking)
      get signing_device_path(device.public_token) # rides the device token into the session
      card = booking.create_guest_registration_card!(hotel: hotel)

      get guest_registration_card_path(card.public_token)
      expect(response.body).to include("Wrong reservation? Send tablet back")
      expect(response.body).to include(release_signing_device_path(device.public_token))

      post release_signing_device_path(device.public_token)
      expect(device.reload.current_booking).to be_nil
    end

    it "does not offer the back control to a guest signing on their own phone" do
      card = booking.create_guest_registration_card!(hotel: hotel)

      get guest_registration_card_path(card.public_token)

      expect(response.body).not_to include("Wrong reservation? Send tablet back")
    end
  end
end
