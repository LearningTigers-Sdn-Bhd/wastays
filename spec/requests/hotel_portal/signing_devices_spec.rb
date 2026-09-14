# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::SigningDevices", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
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

  it "renders the enrolment page on the tablet" do
    get new_hotel_signing_device_path(hotel)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Use this tablet")
  end

  it "enrols the tablet and leaves it on the kiosk page" do
    expect { post hotel_signing_device_path(hotel), params: { signing_device: { label: "Lobby tablet" } } }
      .to change { hotel.signing_devices.count }.by(1)

    device = hotel.signing_devices.last
    expect(device.label).to eq("Lobby tablet")
    expect(response).to redirect_to(signing_device_path(device.public_token))
  end

  # The whole security model: what is left on the counter must not be able to
  # reach the portal. If this passes while the session survives, a guest holding
  # the tablet is one back-button from the booking list.
  it "signs the staff member out of the tablet" do
    post hotel_signing_device_path(hotel), params: { signing_device: { label: "Lobby tablet" } }

    get hotel_dashboard_path(hotel)
    expect(response).not_to have_http_status(:ok)
  end

  it "names the tablet even when the label is left blank" do
    post hotel_signing_device_path(hotel), params: { signing_device: { label: "  " } }

    expect(hotel.signing_devices.last.label).to be_present
  end

  it "refuses a user who cannot manage bookings" do
    role.permissions.destroy_all

    expect { post hotel_signing_device_path(hotel), params: { signing_device: { label: "Nope" } } }
      .not_to change { hotel.signing_devices.count }
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
