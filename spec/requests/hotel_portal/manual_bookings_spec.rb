# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::ManualBookings", type: :request do
  let(:hotel) { create(:hotel, status: "live") }
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

  describe "Reservations bookings tab" do
    let!(:booking1) { create(:booking, hotel: hotel, guest_name: "Alice Smith", status: "confirmed", confirmation_token: "WS-ALICE") }
    let!(:booking2) { create(:booking, hotel: hotel, guest_name: "Bob Jones", status: "cancelled", confirmation_token: "WS-BOB") }

    it "returns all bookings by default" do
      get hotel_front_desk_path(hotel), params: { tab: "bookings", view: "list" }
      expect(response.body).to include("Alice Smith")
      expect(response.body).to include("Bob Jones")
    end

    it "filters by query (name)" do
      get hotel_front_desk_path(hotel), params: { tab: "bookings", view: "list", booking_query: "Alice" }
      expect(response.body).to include("Alice Smith")
      expect(response.body).not_to include("Bob Jones")
    end

    it "filters by query (reference)" do
      get hotel_front_desk_path(hotel), params: { tab: "bookings", view: "list", booking_query: "WS-BOB" }
      expect(response.body).not_to include("Alice Smith")
      expect(response.body).to include("Bob Jones")
    end

    it "filters by status" do
      get hotel_front_desk_path(hotel), params: { tab: "bookings", view: "list", booking_status: "cancelled" }
      expect(response.body).not_to include("Alice Smith")
      expect(response.body).to include("Bob Jones")
    end

    it "combines query and status" do
      get hotel_front_desk_path(hotel), params: { tab: "bookings", view: "list", booking_query: "Alice", booking_status: "cancelled" }
      expect(response.body).not_to include("Alice Smith")
      expect(response.body).not_to include("Bob Jones")
    end

    it "resets date-filtered empty results in both views" do
      params = { tab: "bookings", booking_start_date: "2099-01-01", booking_end_date: "2099-01-01" }

      get hotel_front_desk_path(hotel), params: params.merge(view: "list")
      expect(Nokogiri::HTML(response.body).at_css("a[aria-label='Reset booking filters']")&.[]("href")).to eq(hotel_front_desk_path(hotel, tab: "bookings", view: "list"))

      get hotel_front_desk_path(hotel), params: params.merge(view: "rooms")
      expect(Nokogiri::HTML(response.body).at_css("a[aria-label='Reset booking filters']")&.[]("href")).to eq(hotel_front_desk_path(hotel, tab: "bookings", view: "rooms"))
    end
  end

  describe "POST /booking-actions/new-booking" do
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
        post hotel_booking_action_new_booking_path(hotel), params: valid_params
      }.to change(Booking, :count).by(1)

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, Booking.last))
      expect(Booking.last.booking_folio).to be_present
      expect(BookingFolio.where(booking: Booking.last).count).to eq(1)

      # Check inventory deduction
      inventory = room_type.room_inventories.find_by(date: Date.current)
      expect(inventory.quantity).to eq(9) # 10 - 1
    end
  end

  describe "quick and grouped booking creation" do
    let(:rate_plan) { create(:rate_plan, room_type: room_type) }

    it "launches new booking through the quick booking sheet" do
      get hotel_front_desk_path(hotel), params: { tab: "bookings", view: "list" }

      document = Nokogiri::HTML(response.body)
      new_booking_link = document.at_css("a[href='#{hotel_booking_action_quick_booking_path(hotel)}']")

      expect(new_booking_link.text.squish).to eq("New Booking")
      expect(new_booking_link["data-turbo-frame"]).to eq("booking_action_sheet")
      expect(response.body).not_to include("Full Booking")
      expect(document.at_css("a[href='#{hotel_booking_action_new_booking_path(hotel)}']")).to be_nil
    end

    it "renders quick booking as a compact room-row form" do
      get hotel_booking_action_quick_booking_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Quick Booking", "Every row creates one room booking", "Confirm booking")
      expect(response.body).to include('dialog id="booking-creation-sheet"')
      expect(response.body).to include('data-panels-ui-sheet-side="right"')
      expect(response.body).to include("bg-muted")
      expect(response.body).to include("Phone", "+60 12-345 6789", "guest@example.com")
      expect(response.body).not_to include(">Mobile</label>")
      expect(response.body.scan('data-booking-room-rows-target="row"').size).to eq(1)
      expect(Nokogiri::HTML(response.body).at_css('[data-role="room-number"] select')).not_to have_attribute("required")
    end

    it "keeps quick booking row values and emits a toast when creation fails" do
      params = {
        booking: {
          guest_name: "Toast Guest", guest_email: "toast@example.com", guest_phone: "60123456789",
          check_in: Date.current, check_out: Date.current + 2.days,
          source: "phone",
          rooms: {
            "0" => { room_type_id: "", rate_plan_id: rate_plan.id, room_number: "", adults: 2, children: 0 }
          }
        }
      }

      expect {
        post hotel_booking_action_quick_booking_path(hotel), params: params, headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
      }.not_to change(Booking, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('turbo-stream action="append" target="toast-viewport"')
      expect(response.body).to include("Each reservation row requires a room category.")
      expect(response.body).to include(%(data-preserved-rate-plan="#{rate_plan.id}"))
      expect(response.body).not_to include("prohibited this booking from being saved")
    end

    it "rejects composite room row keys because Rails filters them from strong params" do
      params = {
        booking: {
          guest_name: "Composite Key", guest_email: "composite@example.com", guest_phone: "60123456789",
          check_in: Date.current, check_out: Date.current + 2.days,
          source: "phone",
          rooms: {
            "1750000000000_0" => { room_type_id: room_type.id, rate_plan_id: rate_plan.id, room_number: "101", adults: 1, children: 0 }
          }
        }
      }

      expect {
        post hotel_booking_action_quick_booking_path(hotel), params: params, headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
      }.not_to change(Booking, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Add at least one room.")
    end

    it "creates a quick booking when room row keys are numeric" do
      params = {
        booking: {
          guest_name: "Numeric Key", guest_email: "numeric@example.com", guest_phone: "60123456789",
          check_in: Date.current, check_out: Date.current + 2.days,
          source: "phone",
          rooms: {
            "0" => { room_type_id: room_type.id, rate_plan_id: rate_plan.id, room_number: "101", adults: 1, children: 0 }
          }
        }
      }

      expect {
        post hotel_booking_action_quick_booking_path(hotel), params: params
      }.to change(Booking, :count).by(1)

      booking_room = Booking.last.booking_rooms.first
      expect(booking_room.room_number).to eq("101")
      expect(booking_room.rate_plan_id).to eq(rate_plan.id)
      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, Booking.last))
    end

    it "hydrates the full booking form from nested quick booking params" do
      get hotel_booking_action_new_booking_path(hotel), params: {
        booking: {
          guest_name: "Quick Carry", guest_email: "carry@example.com", guest_phone: "60199887766",
          check_in: Date.current, check_out: Date.current + 2.days,
          source: "whatsapp",
          rooms: {
            "0" => { room_type_id: room_type.id, rate_plan_id: rate_plan.id, room_number: "101", adults: 2, children: 1 }
          }
        }
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New Booking", "Quick Carry", "carry@example.com", "60199887766")
      expect(response.body).to include(
        %(data-preserved-room-type="#{room_type.id}"),
        %(data-preserved-rate-plan="#{rate_plan.id}"),
        %(data-preserved-room-number="101")
      )
    end

    it "creates one child booking per room row and redirects to the group control panel" do
      params = {
        booking: {
          guest_name: "Group Lead", guest_email: "lead@example.com", guest_phone: "60123456789",
          check_in: Date.current, check_out: Date.current + 2.days,
          source: "phone",
          rooms: {
            "0" => { room_type_id: room_type.id, room_number: "101", adults: 2, children: 0 },
            "1" => { room_type_id: room_type.id, room_number: "102", adults: 1, children: 1 }
          }
        }
      }

      expect {
        post hotel_booking_action_quick_booking_path(hotel), params: params
      }.to change(Booking, :count).by(2).and change(GroupBooking, :count).by(1)

      group = GroupBooking.last
      expect(BookingRoom.where(booking: group.bookings).pluck(:room_number)).to contain_exactly("101", "102")
      expect(group.bookings.pluck(:payment_status)).to all(eq("pending"))
      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, group.bookings.first, scope: "group"))
    end

    it "records one group deposit and allocates it across child folios" do
      PaymentMethods::EnsureDefaults.call(hotel)
      method = hotel.hotel_payment_methods.active.find_by!(guest_advance: true)
      params = {
        booking: {
          guest_name: "Paying Group", guest_email: "payer@example.com", guest_phone: "60111222333",
          check_in: Date.current, check_out: Date.current + 2.days, source: "phone",
          collect_payment: "1", hotel_payment_method_id: method.id,
          rooms: {
            "0" => { room_type_id: room_type.id, room_number: "101", adults: 1, children: 0 },
            "1" => { room_type_id: room_type.id, room_number: "102", adults: 1, children: 0 }
          }
        }
      }

      expect {
        post hotel_booking_action_new_booking_path(hotel), params: params
      }.to change(Deposit, :count).by(1).and change(DepositMovement.movement_type_apply, :count).by(2)

      group = GroupBooking.last
      # One aggregate prepayment for the whole group, allocated across both folios.
      expect(group.deposits.last).to have_attributes(
        kind: "prepayment", amount: group.bookings.sum(&:total_amount), status: "settled"
      )
      expect(group.bookings.pluck(:payment_status)).to all(eq("captured"))
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

      expect(response).to redirect_to(hotel_booking_workspace_path(hotel, booking, tab: "booking_details"))

      # Old date inventory should be released (back to 10)
      expect(room_type.room_inventories.find_by(date: Date.current).quantity).to eq(10)
      # New date inventory should be deducted (to 9)
      expect(room_type.room_inventories.find_by(date: Date.current + 1.day).quantity).to eq(9)
    end
  end
end
