# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ManualBookings", type: :request do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 10, base_price: 100, room_numbers: [ "101", "102", "103" ]) }

  before do
    role = create(:role, account: hotel.account)
    %w[view_bookings manage_bookings].each do |slug|
      permission = Permission.find_by(slug: slug) || create(:permission, name: slug.titleize, slug: slug)
      role.permissions << permission
    end
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
    create(:room_rate, room_type: room_type, date: Date.current, price: 100, currency: hotel.default_currency.presence || "MYR")
    create(:room_rate, room_type: room_type, date: Date.current + 1.day, price: 100, currency: hotel.default_currency.presence || "MYR")
  end

  describe "GET /index" do
    let!(:booking1) { create(:booking, hotel: hotel, guest_name: "Alice Smith", status: "confirmed", confirmation_token: "WS-ALICE") }
    let!(:booking2) { create(:booking, hotel: hotel, guest_name: "Bob Jones", status: "cancelled", confirmation_token: "WS-BOB") }

    it "returns all bookings by default" do
      get "/hotel/#{hotel.id}/bookings"
      expect(response.body).to include("Alice Smith")
      expect(response.body).to include("Bob Jones")
    end

    it "filters by query (name)" do
      get "/hotel/#{hotel.id}/bookings", params: { query: "Alice" }
      expect(response.body).to include("Alice Smith")
      expect(response.body).not_to include("Bob Jones")
    end

    it "filters by query (reference)" do
      get "/hotel/#{hotel.id}/bookings", params: { query: "WS-BOB" }
      expect(response.body).not_to include("Alice Smith")
      expect(response.body).to include("Bob Jones")
    end

    it "filters by status" do
      get "/hotel/#{hotel.id}/bookings", params: { status: "cancelled" }
      expect(response.body).not_to include("Alice Smith")
      expect(response.body).to include("Bob Jones")
    end

    it "combines query and status" do
      get "/hotel/#{hotel.id}/bookings", params: { query: "Alice", status: "cancelled" }
      expect(response.body).not_to include("Alice Smith")
      expect(response.body).not_to include("Bob Jones")
    end
  end

  describe "POST /booking-transactions/new-booking" do
    let(:valid_params) do
      {
        booking: {
          guest_name: "John Doe",
          guest_email: "john@example.com",
          guest_phone: "123456789",
          check_in: Date.current,
          check_out: Date.current + 2.days,
          room_type_id: room_type.id,
          room_number: "101",
          adults: 2
        }
      }
    end

    it "creates a new booking and deducts inventory" do
      expect {
        post hotel_booking_transaction_new_booking_path(hotel), params: valid_params
      }.to change(Booking, :count).by(1)

      expect(response).to redirect_to(hotel_booking_path(hotel, Booking.last))

      # Check inventory deduction
      inventory = room_type.room_inventories.find_by(date: Date.current)
      expect(inventory.quantity).to eq(9) # 10 - 1
    end
  end

  describe "GET /availability" do
    it "returns available room numbers" do
      room_type.update!(room_numbers: [ "101", "102", "103" ])

      get "/hotel/#{hotel.id}/bookings/availability", params: {
        check_in: Date.current,
        check_out: Date.current + 1.day,
        room_type_id: room_type.id
      }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["available_rooms"]).to include("101", "102", "103")
    end
  end

  describe "PATCH /update" do
    let(:booking) { create(:booking, hotel: hotel, check_in: Date.current, check_out: Date.current + 1.day) }
    let!(:booking_room) { create(:booking_room, booking: booking, room_type: room_type) }

    it "updates stay dates and syncs inventory" do
      # Initial inventory deduction
      InventoryManager = Bookings::InventoryManager.new(booking)
      InventoryManager.deduct

      old_inventory = room_type.room_inventories.find_by(date: Date.current).quantity # Should be 9

      patch "/hotel/#{hotel.id}/bookings/#{booking.id}", params: {
        booking: {
          check_in: Date.current + 1.day,
          check_out: Date.current + 2.days
        }
      }

      expect(response).to redirect_to(hotel_booking_path(hotel, booking))

      # Old date inventory should be released (back to 10)
      expect(room_type.room_inventories.find_by(date: Date.current).quantity).to eq(10)
      # New date inventory should be deducted (to 9)
      expect(room_type.room_inventories.find_by(date: Date.current + 1.day).quantity).to eq(9)
    end
  end
end
