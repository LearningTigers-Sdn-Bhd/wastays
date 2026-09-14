# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::SigningHandoffs", type: :request do
  let(:hotel) { create(:hotel, status: "live", guest_registration_card_terms: "House rules apply.") }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel) }
  let!(:device) { hotel.signing_devices.create!(label: "Front desk tablet") }
  let!(:primary) { create(:booking_guest, booking: booking, guest: create(:guest), is_primary: true) }

  before do
    role.permissions << Permission.find_or_create_by!(slug: "manage_bookings") { |p| p.name = "Manage Bookings" }
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def handoff(token: device.public_token)
    post hotel_booking_signing_handoff_path(hotel, booking), params: { device_token: token }
  end

  it "hands the stay to the device and broadcasts where to go" do
    expect { handoff }.to change { device.reload.current_booking }.from(nil).to(booking)

    expect(response).to be_redirect
    expect(flash[:notice]).to include("Front desk tablet")
  end

  it "broadcasts a navigate instruction, and puts no guest token on the wire" do
    card = create(:guest_registration_card, hotel: hotel, booking: booking, booking_guest: primary)

    handoff
    payload = turbo_broadcasts_to(device, :signing).join

    expect(payload).to include("signing-device/#{device.public_token}/next")
    # The tablet fetches the card itself, so overhearing this stream reveals
    # which tablet is busy and nothing about who is signing.
    expect(payload).not_to include(card.public_token)
  end

  it "refuses a booking whose guests have all signed" do
    create(:guest_registration_card, :signed, hotel: hotel, booking: booking, booking_guest: primary)

    expect { handoff }.not_to change { device.reload.current_booking }
    expect(flash[:alert]).to include("already signed")
  end

  it "refuses when the property has no registration terms to sign against" do
    hotel.update!(guest_registration_card_terms: nil)

    expect { handoff }.not_to change { device.reload.current_booking }
    expect(flash[:alert]).to include("terms")
  end

  describe "a tablet that is already busy" do
    let(:other_booking) { create(:booking, hotel: hotel) }
    let!(:other_guest) { create(:booking_guest, booking: other_booking, guest: create(:guest), is_primary: true) }

    before { device.hand_stay(other_booking) }

    # The guest standing at the tablet is on the card page, which does not
    # listen to the device stream. Stealing the tablet would leave them signing
    # away undisturbed and then drop whoever was left on their booking.
    it "refuses to steal it, and says what it is doing" do
      expect { handoff }.not_to change { device.reload.current_booking }
      expect(flash[:alert]).to include("still signing")
    end

    it "frees itself once that stay has signed elsewhere" do
      create(:guest_registration_card, :signed, hotel: hotel, booking: other_booking, booking_guest: other_guest)

      expect { handoff }.to change { device.reload.current_booking }.to(booking)
    end

    # The usual reason for a second push is a tablet that slept through the
    # first, so the same stay is a retry rather than a conflict.
    it "accepts the same stay again" do
      device.hand_stay(booking)

      handoff
      expect(flash[:alert]).to be_blank
      expect(turbo_broadcasts_to(device, :signing).join).to include("signing-device/#{device.public_token}/next")
    end
  end

  describe "what the desk is told about the tablet" do
    it "says the card is ready when the tablet has beaten recently" do
      device.update!(last_seen_at: 5.seconds.ago)
      handoff

      expect(flash[:notice]).to include("can sign there now")
    end

    # Still sent: a beat can fail for reasons the tablet survives, and refusing
    # would brick the feature every time it did.
    it "warns, rather than refusing, when the tablet has gone quiet" do
      device.update!(last_seen_at: 10.minutes.ago)

      expect { handoff }.to change { device.reload.current_booking }.to(booking)
      expect(flash[:notice]).to include("has not checked in recently")
    end
  end

  it "will not drive a device belonging to another property" do
    other = create(:hotel, status: "live").signing_devices.create!(label: "Someone else's tablet")

    expect { handoff(token: other.public_token) }.not_to change { other.reload.current_booking }
    expect(flash[:alert]).to be_present
  end
end
