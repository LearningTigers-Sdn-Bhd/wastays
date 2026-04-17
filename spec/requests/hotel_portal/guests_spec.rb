require "rails_helper"
require "cgi"

RSpec.describe "HotelPortal::Guests", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /index" do
    it "renders guests in a table layout" do
      guest = Guest.create!(
        name: "Ravi Menon",
        email: "ravi@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        country: "India",
        gender: "male",
        document_type: "passport"
      )

      booking = create(
        :booking,
        hotel: hotel,
        status: "completed",
        guest_name: guest.name,
        guest_email: guest.email,
        guest_phone: guest.phone,
        check_out: Date.new(2026, 4, 2),
        total_amount: 720.0,
        currency: "MYR"
      )
      booking.update_column(:checked_out_at, Time.zone.parse("2026-04-02 14:30:00"))
      create(:booking_guest, booking: booking, guest: guest, is_primary: true)

      get hotel_guests_path(hotel)

      expect(response).to have_http_status(:success)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("<table")
      expect(body_text).to include("Ravi Menon")
      expect(body_text).to include(hotel.name[0...10])
      expect(body_text).to include("Guest Records")
      expect(body_text).to include("Country")
      expect(body_text).to include("Stays")
      expect(body_text).to include("Last Stayed")
      expect(body_text).to include("Lifetime Value")
      expect(body_text).to include("02:30 PM")
      expect(body_text).to include("View Timeline")
    end

    it "filters guests by search query and country" do
      ravi = Guest.create!(
        name: "Ravi Menon",
        email: "ravi@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        country: "India",
        gender: "male",
        document_type: "passport"
      )
      aisha = Guest.create!(
        name: "Aisha Tan",
        email: "aisha@example.com",
        phone: "+60199887766",
        government_id: "900101015555",
        country: "Malaysia",
        gender: "female",
        document_type: "ic"
      )

      ravi_booking = create(:booking, hotel: hotel, guest_name: ravi.name, guest_email: ravi.email, guest_phone: ravi.phone)
      aisha_booking = create(:booking, hotel: hotel, guest_name: aisha.name, guest_email: aisha.email, guest_phone: aisha.phone)
      create(:booking_guest, booking: ravi_booking, guest: ravi, is_primary: true)
      create(:booking_guest, booking: aisha_booking, guest: aisha, is_primary: true)

      get hotel_guests_path(hotel), params: { query: "ravi", country: "India" }

      expect(response).to have_http_status(:success)
      body_text = CGI.unescapeHTML(response.body)
      expect(body_text).to include("Search guests")
      expect(body_text).to include("All Countries")
      expect(body_text).to include("Ravi Menon")
      expect(body_text).not_to include("Aisha Tan")
    end
  end

  describe "GET /show" do
    it "renders the guest timeline without grouped query errors" do
      guest = Guest.create!(
        name: "Ravi Menon",
        email: "ravi@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        country: "India",
        gender: "male",
        document_type: "passport"
      )

      myr_booking = create(
        :booking,
        hotel: hotel,
        status: "completed",
        guest_name: guest.name,
        guest_email: guest.email,
        guest_phone: guest.phone,
        currency: "MYR",
        total_amount: 720.0
      )
      usd_booking = create(
        :booking,
        hotel: hotel,
        status: "completed",
        guest_name: guest.name,
        guest_email: guest.email,
        guest_phone: guest.phone,
        currency: "USD",
        total_amount: 100.0
      )
      create(:booking_guest, booking: myr_booking, guest: guest, is_primary: true)
      create(:booking_guest, booking: usd_booking, guest: guest)

      get hotel_guest_path(hotel, guest)
      body_text = CGI.unescapeHTML(response.body)

      expect(response).to have_http_status(:success)
      expect(body_text).to include(hotel.name[0...10])
      expect(body_text).to include("Guest Records")
      expect(body_text).to include("Ravi Menon")
      expect(body_text).to include("Guest Profile")
      expect(body_text).to include("Currency Totals")
      expect(body_text).to include("Booking History")
      expect(body_text).to include("Confirmation")
      expect(body_text).to include("Pre-Check-In")
      expect(body_text).to include("MYR")
      expect(body_text).to include("USD")
      expect(body_text.downcase).to include("india")
    end
  end
end
