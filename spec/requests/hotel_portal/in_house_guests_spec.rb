require "rails_helper"

RSpec.describe "HotelPortal::InHouseGuests", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:other_hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel, name: "Deluxe Room") }
  let(:primary_guest) do
    create(
      :guest,
      name: "Aisha Tan",
      email: "aisha.tan@example.com",
      phone: "+60123456789",
      country: "Malaysia",
      gender: "female",
      document_type: "passport",
      government_id: "P1234567"
    )
  end
  let(:secondary_guest) do
    create(
      :guest,
      name: "Ben Lim",
      email: "ben.lim@example.com",
      phone: "+60129876543",
      country: "Malaysia",
      gender: "male",
      document_type: "passport",
      government_id: "P7654321"
    )
  end
  let(:in_house_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "checked_in",
      confirmation_token: "WS-INHOUSE-001",
      guest_name: primary_guest.name,
      guest_email: primary_guest.email,
      guest_phone: primary_guest.phone,
      checked_in_at: Time.zone.local(2026, 4, 16, 10, 30),
      checked_out_at: nil
    )
  end
  let(:newer_in_house_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "checked_in",
      confirmation_token: "WS-INHOUSE-002",
      guest_name: secondary_guest.name,
      guest_email: secondary_guest.email,
      guest_phone: secondary_guest.phone,
      checked_in_at: Time.zone.local(2026, 4, 16, 11, 30),
      checked_out_at: nil
    )
  end
  let(:completed_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "completed",
      confirmation_token: "WS-COMPLETED-001",
      guest_name: "Completed Guest",
      guest_email: "completed@example.com",
      guest_phone: "+60111111111",
      checked_in_at: Time.zone.local(2026, 4, 15, 15, 0),
      checked_out_at: Time.zone.local(2026, 4, 16, 11, 0)
    )
  end
  let(:cancelled_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "cancelled",
      confirmation_token: "WS-CANCELLED-001",
      guest_name: "Cancelled Guest",
      guest_email: "cancelled@example.com",
      guest_phone: "+60122222222",
      checked_in_at: Time.zone.local(2026, 4, 16, 9, 0),
      checked_out_at: nil
    )
  end
  let(:date_only_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "confirmed",
      confirmation_token: "WS-DATEONLY-001",
      guest_name: "Date Only Guest",
      guest_email: "date.only@example.com",
      guest_phone: "+60133333333",
      checked_in_at: nil,
      checked_out_at: nil
    )
  end
  let(:checked_in_timestamp_but_not_checked_in_booking) do
    create(
      :booking,
      hotel: hotel,
      status: "confirmed",
      confirmation_token: "WS-TIMESTAMP-001",
      guest_name: "Timestamp Only Guest",
      guest_email: "timestamp.only@example.com",
      guest_phone: "+60155555555",
      checked_in_at: Time.zone.local(2026, 4, 16, 13, 0),
      checked_out_at: nil
    )
  end
  let(:other_hotel_booking) do
    create(
      :booking,
      hotel: other_hotel,
      status: "checked_in",
      confirmation_token: "WS-OTHER-001",
      guest_name: "Other Hotel Guest",
      guest_email: "other.hotel@example.com",
      guest_phone: "+60144444444",
      checked_in_at: Time.zone.local(2026, 4, 16, 12, 0),
      checked_out_at: nil
    )
  end

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)

    attach_booking_details(in_house_booking, primary_guest)
    attach_booking_details(newer_in_house_booking, secondary_guest)
  end

  def attach_booking_details(booking, guest)
    BookingRoom.create!(
      booking: booking,
      room_type: room_type,
      room_type_snapshot: { "name" => room_type.name },
      quantity: 1,
      subtotal: booking.total_amount
    )
    create(:booking_guest, booking: booking, guest: guest, is_primary: true)
  end

  describe "GET /index" do
    it "shows only current hotel's checked-in bookings that have not checked out" do
      completed_booking
      cancelled_booking
      date_only_booking
      checked_in_timestamp_but_not_checked_in_booking
      other_hotel_booking

      get "/hotel/#{hotel.id}/in_house_guests"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("In-House Guests")
      expect(response.body).to include("Guests currently checked in at your hotel.")
      expect(response.body).to include(in_house_booking.guest_name)
      expect(response.body).to include(in_house_booking.confirmation_token)
      expect(response.body).not_to include(completed_booking.guest_name)
      expect(response.body).not_to include(cancelled_booking.guest_name)
      expect(response.body).not_to include(date_only_booking.guest_name)
      expect(response.body).not_to include(checked_in_timestamp_but_not_checked_in_booking.guest_name)
      expect(response.body).not_to include(other_hotel_booking.guest_name)
    end

    it "searches in-house guests by booking reference" do
      completed_booking
      cancelled_booking
      date_only_booking
      checked_in_timestamp_but_not_checked_in_booking
      other_hotel_booking

      get "/hotel/#{hotel.id}/in_house_guests", params: { query: in_house_booking.confirmation_token }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(in_house_booking.confirmation_token)
      expect(response.body).not_to include(completed_booking.confirmation_token)
      expect(response.body).not_to include(cancelled_booking.confirmation_token)
      expect(response.body).not_to include(date_only_booking.confirmation_token)
      expect(response.body).not_to include(checked_in_timestamp_but_not_checked_in_booking.confirmation_token)
      expect(response.body).not_to include(other_hotel_booking.confirmation_token)
    end

    it "searches in-house guests by email" do
      completed_booking
      cancelled_booking
      date_only_booking
      checked_in_timestamp_but_not_checked_in_booking
      other_hotel_booking

      get "/hotel/#{hotel.id}/in_house_guests", params: { query: in_house_booking.guest_email }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(in_house_booking.guest_email)
      expect(response.body).not_to include(newer_in_house_booking.guest_email)
      expect(response.body).not_to include(completed_booking.guest_email)
      expect(response.body).not_to include(cancelled_booking.guest_email)
      expect(response.body).not_to include(date_only_booking.guest_email)
      expect(response.body).not_to include(checked_in_timestamp_but_not_checked_in_booking.guest_email)
      expect(response.body).not_to include(other_hotel_booking.guest_email)
    end

    it "searches in-house guests by phone" do
      completed_booking
      cancelled_booking
      date_only_booking
      checked_in_timestamp_but_not_checked_in_booking
      other_hotel_booking

      get "/hotel/#{hotel.id}/in_house_guests", params: { query: in_house_booking.guest_phone }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(in_house_booking.guest_phone)
      expect(response.body).not_to include(newer_in_house_booking.guest_phone)
      expect(response.body).not_to include(completed_booking.guest_phone)
      expect(response.body).not_to include(cancelled_booking.guest_phone)
      expect(response.body).not_to include(date_only_booking.guest_phone)
      expect(response.body).not_to include(checked_in_timestamp_but_not_checked_in_booking.guest_phone)
      expect(response.body).not_to include(other_hotel_booking.guest_phone)
    end

    it "orders newest checked-in stays first" do
      completed_booking
      cancelled_booking
      date_only_booking
      checked_in_timestamp_but_not_checked_in_booking
      other_hotel_booking

      get "/hotel/#{hotel.id}/in_house_guests"

      expect(response).to have_http_status(:success)
      expect(response.body.index(newer_in_house_booking.guest_name)).to be < response.body.index(in_house_booking.guest_name)
    end
  end
end
