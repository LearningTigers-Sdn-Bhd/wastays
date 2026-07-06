require "rails_helper"
require "cgi"

RSpec.describe "HotelPortal::Bookings::GuestRegistrationCards", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    %w[manage_bookings view_bookings].each do |slug|
      role.permissions << (Permission.find_by(slug: slug) || create(:permission, slug: slug))
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/bookings/:booking_id/guest_registration_card" do
    it "creates a draft card on first open and shows guest registration number" do
      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(booking.reload.guest_registration_card).to be_present
      expect(response.body).to include("GRC / Guest Registration No")
      expect(response.body).to include(booking.formatted_guest_registration_number)
      expect(response.body).to include("Please read the terms and conditions carefully before signing")
      expect(response.body.scan("Print official form").size).to eq(1)
      expect(response.body).not_to include("Hotel acknowledgement")
      expect(response.body).not_to include("Cancellation Policy")
    end

    it "shows formatted guest registration number after check-in number exists" do
      booking.update!(guest_registration_number: 1)

      get hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("#{hotel.hotel_prefix}-20000001")
    end
  end

  describe "PATCH /hotel/:hotel_id/bookings/:booking_id/guest_registration_card" do
    it "saves signature and terms snapshot" do
      create(:property_policy, hotel: hotel, check_in_time: "3:00 PM", check_out_time: "11:00 AM", cancellation_policy: "No refund after check-in")

      patch hotel_booking_guest_registration_card_path(hotel, booking), params: {
        guest_registration_card: {
          signer_name: "Jane Guest",
          signature_data_url: "data:image/png;base64,abc123"
        }
      }

      card = booking.reload.guest_registration_card
      expect(response).to redirect_to(hotel_booking_guest_registration_card_path(hotel, booking))
      expect(card).to be_signed
      expect(card.signer_name).to eq("Jane Guest")
      expect(card.signature_data_url).to eq("data:image/png;base64,abc123")
      expect(card.signed_at).to be_present
      expect(card.terms_snapshot).to include("check_in_time" => "3:00 PM", "check_out_time" => "11:00 AM", "cancellation_policy" => "No refund after check-in")
    end

    it "rejects blank signature" do
      patch hotel_booking_guest_registration_card_path(hotel, booking), params: {
        guest_registration_card: {
          signer_name: "Jane Guest",
          signature_data_url: ""
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(CGI.unescapeHTML(response.body)).to include("Signature data url can't be blank")
      expect(response.body).not_to include("Signed by Jane Guest")
    end
  end

  describe "DELETE /hotel/:hotel_id/bookings/:booking_id/guest_registration_card" do
    it "clears a saved signature so the guest can sign again or sign physically" do
      card = create(:guest_registration_card, :signed, booking: booking, hotel: hotel)

      delete hotel_booking_guest_registration_card_path(hotel, booking)

      expect(response).to redirect_to(hotel_booking_guest_registration_card_path(hotel, booking))
      expect(card.reload).to be_draft
      expect(card.signer_name).to be_blank
      expect(card.signature_data_url).to be_blank
      expect(card.signed_at).to be_blank
    end
  end

  describe "booking documents" do
    it "links to the guest registration card from booking show" do
      get hotel_booking_path(hotel, booking)

      expect(response).to have_http_status(:success)
      expect(response.body).to include(hotel_booking_guest_registration_card_path(hotel, booking))
      expect(response.body).to include("Guest Registration Card")
    end
  end
end
