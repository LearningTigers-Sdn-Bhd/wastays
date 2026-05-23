# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ProfessionalBookings", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel: hotel, base_price: 100, room_numbers: [ "101", "102" ]) }
  let(:existing_guest) { create(:guest, created_by_hotel: hotel, name: "Existing Guest", email: "existing@example.com") }

  before do
    hotel.hotel_taxes.create!(name: "SST", amount: 6, rate_type: "percentage")
    role = create(:role, account: hotel.account, name: "Admin", slug: "admin")
    role.permissions << (Permission.find_by(slug: 'view_bookings') || create(:permission, slug: 'view_bookings', name: 'View Bookings'))
    role.permissions << (Permission.find_by(slug: 'manage_bookings') || create(:permission, slug: 'manage_bookings', name: 'Manage Bookings'))
    user.user_hotel_accesses.create!(hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/guests/search" do
    it "returns matching guests for autocomplete" do
      existing_guest # ensure created
      get search_hotel_guests_path(hotel, q: "Exist")

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json.first["name"]).to eq("Existing Guest")
    end
  end

  describe "POST /hotel/:hotel_id/bookings" do
    let(:valid_params) do
      {
        booking: {
          guest_name: "New Guest",
          guest_email: "new@example.com",
          guest_phone: "+60123456789",
          check_in: Date.current,
          check_out: Date.current + 1.day,
          adults: 2,
          room_type_id: room_type.id,
          room_number: "101",
          source: "whatsapp",
          internal_notes: "Needs early check-in",
          manual_rate_override: "150.00",
          total_amount: "150.00"
        }
      }
    end

    it "creates a booking with manual rate override and internal notes" do
      post hotel_bookings_path(hotel), params: valid_params
      expect(response).to redirect_to(hotel_booking_path(hotel, Booking.last)) if Booking.last

      expect(Booking.count).to eq(1)
      booking = Booking.last
      expect(booking.total_amount).to eq(159.0)
      expect(booking.source).to eq("whatsapp")
      expect(booking.internal_notes).to eq("Needs early check-in")
    end

    it "links an existing guest via existing_guest_id" do
      params = valid_params.deep_merge(booking: { existing_guest_id: existing_guest.id })

      expect {
        post hotel_bookings_path(hotel), params: params
      }.to change(Booking, :count).by(1)

      booking = Booking.last
      expect(booking.guests).to include(existing_guest)
    end
  end
end
