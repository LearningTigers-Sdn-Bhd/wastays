# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::SigningDevices", type: :request do
  # Off for every property until a superadmin grants it, so every spec here
  # starts from a hotel that has been granted it.
  let(:hotel) { create(:hotel, status: "live", grc_tablet_signing_enabled: true) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }

  def grant(slug)
    role.permissions << Permission.find_or_create_by!(slug: slug) { |p| p.name = slug.humanize }
  end

  before do
    grant("manage_bookings")
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "the tablet manager" do
    it "lists paired tablets with their state" do
      hotel.signing_devices.create!(label: "Lobby tablet", last_seen_at: Time.current)

      get hotel_signing_devices_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Lobby tablet", "Ready")
    end

    it "renames a tablet" do
      device = hotel.signing_devices.create!(label: "Lobby tablet")

      patch hotel_signing_device_path(hotel, device), params: { signing_device: { label: "Front desk" } }

      expect(device.reload.label).to eq("Front desk")
    end

    # The token is the whole of the device's access, so revoking has to remove
    # the row. A flag would leave a working tablet on the counter.
    it "revokes a tablet outright, and its token stops working" do
      device = hotel.signing_devices.create!(label: "Lobby tablet")

      expect { delete hotel_signing_device_path(hotel, device) }
        .to change { hotel.signing_devices.count }.by(-1)

      reset!
      get signing_device_path(device.public_token)
      expect(response).not_to have_http_status(:ok)
    end

    it "refuses a user who cannot manage bookings" do
      role.permissions.destroy_all

      get hotel_signing_devices_path(hotel)

      expect(response).not_to have_http_status(:ok)
    end
  end

  # A pairing is minted at the desk and claimed on the tablet, so staff
  # credentials never reach the device that ends up holding the token.
  describe "pairing a tablet" do
    it "mints a pairing and shows its QR and code" do
      expect { post hotel_signing_device_pairings_path(hotel) }
        .to change { hotel.signing_device_pairings.count }.by(1)

      get hotel_signing_devices_path(hotel)
      pairing = hotel.signing_device_pairings.last

      expect(response.body).to include(pairing.display_code)
      # The QR is rendered inline as a data URL, so there is no second request
      # carrying the token.
      expect(response.body).to include("data:image/svg+xml;base64,")
    end

    it "claims a pairing on the tablet, with no session, and lands on the kiosk" do
      post hotel_signing_device_pairings_path(hotel)
      pairing = hotel.signing_device_pairings.last

      reset!
      get pair_token_path(pairing.token)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(CGI.escapeHTML(hotel.name))

      expect { post claim_pair_token_path(pairing.token), params: { label: "Lobby tablet" } }
        .to change { hotel.signing_devices.count }.by(1)

      device = hotel.signing_devices.last
      expect(device.label).to eq("Lobby tablet")
      expect(response).to redirect_to(signing_device_path(device.public_token))
      expect(pairing.reload.signing_device).to eq(device)
    end

    it "offers a code form for a tablet whose camera will not focus" do
      reset!
      get pair_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pair this tablet")
    end

    it "finds a pairing by its typed code, however it was typed" do
      post hotel_signing_device_pairings_path(hotel)
      pairing = hotel.signing_device_pairings.last

      reset!
      post pair_lookup_path, params: { code: pairing.display_code.downcase }

      expect(response).to redirect_to(pair_token_path(pairing.token))
    end

    # Single use is what makes a QR left up on a screen worthless: the first
    # tablet takes it and the second gets nothing.
    it "cannot be claimed twice" do
      post hotel_signing_device_pairings_path(hotel)
      pairing = hotel.signing_device_pairings.last

      reset!
      post claim_pair_token_path(pairing.token), params: { label: "First" }

      expect { post claim_pair_token_path(pairing.token), params: { label: "Second" } }
        .not_to change { hotel.signing_devices.count }
      expect(response).to redirect_to(pair_path)
    end

    it "refuses an expired pairing" do
      post hotel_signing_device_pairings_path(hotel)
      pairing = hotel.signing_device_pairings.last
      pairing.update!(expires_at: 1.second.ago)

      reset!
      expect { post claim_pair_token_path(pairing.token), params: { label: "Too late" } }
        .not_to change { hotel.signing_devices.count }
    end

    # Telling a guesser apart from an honest typo would tell them whether the
    # code exists, so both get the same answer.
    it "says the same thing for a wrong code as for an expired one" do
      reset!
      post pair_lookup_path, params: { code: "ZZZ999" }

      expect(response).to redirect_to(pair_path)
      expect(flash[:alert]).to include("not valid")
    end
  end

  # The feature is granted per property by a superadmin. Every entry point
  # re-checks, because the navigation only hides the link.
  describe "without the superadmin grant" do
    let(:hotel) { create(:hotel, status: "live", grc_tablet_signing_enabled: false) }

    it "refuses the tablet manager" do
      get hotel_signing_devices_path(hotel)

      expect(response).to redirect_to(hotel_dashboard_path(hotel))
    end

    it "refuses to mint a pairing" do
      expect { post hotel_signing_device_pairings_path(hotel) }
        .not_to change { hotel.signing_device_pairings.count }
    end

    # A tablet paired while the grant was live stops working when it is
    # withdrawn, rather than quietly carrying on.
    it "stops an already-paired tablet" do
      hotel.update_column(:grc_tablet_signing_enabled, true)
      device = hotel.signing_devices.create!(label: "Lobby tablet")
      hotel.update_column(:grc_tablet_signing_enabled, false)

      reset!
      get signing_device_path(device.public_token)

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "the kiosk page itself" do
    let!(:device) { hotel.signing_devices.create!(label: "Lobby tablet") }

    it "is reachable with no session at all" do
      reset!
      get signing_device_path(device.public_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ready to sign")
    end

    it "records that the tablet is alive" do
      expect { get signing_device_path(device.public_token) }.to change { device.reload.last_seen_at }.from(nil)
    end

    # What lets a property leave the screen off between guests. The desk pushes
    # to a sleeping tablet, the broadcast lands on a socket that does not exist,
    # and waking the tablet has to pick the stay up anyway -- otherwise staff
    # have to walk back and press send a second time.
    it "opens straight on the card when it was handed a stay while asleep" do
      booking = create(:booking, hotel: hotel)
      create(:booking_guest, booking: booking, guest: create(:guest), is_primary: true)
      device.hand_stay(booking)

      reset!
      get signing_device_path(device.public_token)

      expect(response).to redirect_to(next_signing_device_path(device.public_token))
    end

    it "stays idle when it is holding nothing" do
      reset!
      get signing_device_path(device.public_token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ready to sign")
    end

    it "carries the heartbeat path, so the idle screen can report in" do
      reset!
      get signing_device_path(device.public_token)

      expect(response.body).to include(heartbeat_signing_device_path(device.public_token))
    end
  end

  describe "the heartbeat" do
    let!(:device) { hotel.signing_devices.create!(label: "Lobby tablet", last_seen_at: 10.minutes.ago) }

    it "keeps a listening tablet alive without a session" do
      reset!

      expect { post heartbeat_signing_device_path(device.public_token) }
        .to change { device.reload.live? }.from(false).to(true)
      expect(response).to have_http_status(:no_content)
    end

    it "goes stale once the beats stop" do
      device.update!(last_seen_at: (SigningDevice::LIVENESS_WINDOW + 1.second).ago)

      expect(device.live?).to be(false)
    end
  end
end
