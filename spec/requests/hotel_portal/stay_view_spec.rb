# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal Stay View", type: :request do
  around { |example| travel_to(Time.zone.local(2026, 7, 16, 10, 0, 0)) { example.run } }

  let(:hotel) { create(:hotel, accounting_business_date: Date.current) }
  let(:user) { create(:user) }
  let(:role) { create(:role, account: hotel.account) }
  let(:room_type) { create(:room_type, hotel:, room_number_mode: "custom", room_numbers: %w[101 102]) }

  def grant(slug)
    permission = Permission.find_by(slug:) || create(:permission, slug:, name: slug.humanize)
    create(:role_permission, role:, permission:)
  end

  def turbo_headers
    { "Accept" => Mime[:turbo_stream].to_s, "Turbo-Frame" => "offcanvas_drawer" }
  end

  before do
    grant("view_bookings")
    grant("manage_bookings")
    grant("manage_guest_arrival")
    grant("manage_room_status")
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/stay-view" do
    it "requires authentication" do
      delete logout_path

      get hotel_stay_view_path(hotel)

      expect(response).to redirect_to(login_path)
    end

    it "renders the timeline board with canonical frame state" do
      booking = create(:booking, hotel:, guest_name: "Ada Lovelace", check_in: Date.current, check_out: Date.current + 2.days)
      create(:booking_room, booking:, room_type:, room_number: "101")

      get hotel_stay_view_path(hotel, view: "timeline", start_date: Date.current, days: 7, density: "comfortable")

      expect(response).to have_http_status(:success)
      expect(response.body).to match(/<turbo-frame[^>]+id="stay_view_board"/)
      expect(response.body).to include("stay-view-timeline", "Ada Lovelace")
      expect(response.body).to include('data-density="compact"')
      expect(response.body).not_to include('id="density-select-menu"')
      expect(response.body).to include('tabs-root--pill', 'data-controller="stay-view--filters"')
      expect(response.body).to include('id="start_date-date-picker"', 'id="days-select-menu"')
      expect(response.body).to include("All room types", "All booking statuses", "All occupancy states", "All physical statuses")
      expect(response.body).to include("Confirmed")
    end

    it "renders Room View from the shared projection" do
      room_type

      get hotel_stay_view_path(hotel, view: "rooms", date: Date.current)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-testid="stay-view-room-cards"', "Room 101", "Room 102")
      expect(response.body).not_to include("stay-view-timeline")
    end

    it "falls back safely for invalid URL state" do
      room_type

      get hotel_stay_view_path(hotel, view: "unknown", start_date: "not-a-date", days: 999, density: "huge")

      expect(response).to have_http_status(:success)
      expect(response.body).to include('data-density="compact"')
      expect(response.body).to include(Date.current.to_fs(:long))
    end

    it "renders only the board frame for a frame request" do
      room_type

      get hotel_stay_view_path(hotel), headers: { "Turbo-Frame" => "stay_view_board" }

      expect(response).to have_http_status(:success)
      expect(response.body).to match(/<turbo-frame[^>]+id="stay_view_board"/)
      expect(response.body).not_to include("Plan stays and manage room operations")
    end

    it "applies filters while retaining all room-type filter options" do
      suite = create(:room_type, hotel:, name: "Suite", room_numbers: [ "201" ])
      create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")
      create(:room_status, hotel:, room_type: suite, room_number: "201", status: "ready")

      get hotel_stay_view_path(hotel, physical_status: "dirty")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Room 101", "Suite")
      expect(response.body).not_to include("Room 201")
    end

    it "redacts booking identity and actions for readiness-only access" do
      role.role_permissions.delete_all
      grant("view_room_readiness")
      booking = create(:booking, hotel:, guest_name: "Sensitive Guest", check_in: Date.current, check_out: Date.current + 2.days)
      create(:booking_room, booking:, room_type:, room_number: "101")

      get hotel_stay_view_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Reserved")
      expect(response.body).not_to include("Sensitive Guest", "Move or reassign", "Change dates")
      expect(response.body).not_to include("#{room_type.id}_101-booking-actions")
    end

    it "rejects users without board access before loading the board" do
      role.role_permissions.delete_all

      get hotel_stay_view_path(hotel)

      expect(response).to redirect_to(root_path)
    end
  end

  describe "booking action sheets" do
    let(:booking) do
      create(:booking, hotel:, guest_name: "Ada Lovelace", check_in: Date.current, check_out: Date.current + 2.days).tap do |record|
        create(:booking_room, booking: record, room_type:, room_number: "101")
      end
    end

    it "renders move and date forms in the off-canvas frame" do
      get edit_hotel_stay_view_booking_move_path(hotel, booking), params: { return_to: hotel_stay_view_path(hotel) }, headers: { "Turbo-Frame" => "offcanvas_drawer" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"', "Move or reassign stay", "Room 102")

      get edit_hotel_stay_view_booking_dates_path(hotel, booking), params: { return_to: hotel_stay_view_path(hotel) }, headers: { "Turbo-Frame" => "offcanvas_drawer" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Change stay dates", "assigned room stays the same")
    end

    it "moves a stay and replaces the complete board over Turbo Stream" do
      patch hotel_stay_view_booking_move_path(hotel, booking), params: {
        return_to: hotel_stay_view_path(hotel, view: :timeline, start_date: Date.current, days: 7),
        booking: { check_in: Date.current + 3.days, room_assignment: "#{room_type.id}|102" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include('target="stay_view_board"', 'target="offcanvas_drawer"', "Stay moved.")
      expect(booking.reload.check_in.to_date).to eq(Date.current + 3.days)
      expect(booking.booking_rooms.first.reload.room_number).to eq("102")
    end

    it "uses a 303 redirect for the HTML mutation fallback" do
      patch hotel_stay_view_booking_dates_path(hotel, booking), params: {
        return_to: hotel_stay_view_path(hotel, view: :rooms, date: Date.current),
        booking: { check_in: Date.current + 1.day, check_out: Date.current + 4.days }
      }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(hotel_stay_view_path(hotel, view: :rooms, date: Date.current))
    end

    it "returns 422 and keeps the proposal form when dates are invalid" do
      patch hotel_stay_view_booking_dates_path(hotel, booking), params: {
        return_to: hotel_stay_view_path(hotel),
        booking: { check_in: Date.current + 3.days, check_out: Date.current + 2.days }
      }, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('target="offcanvas_drawer"', "Checkout must be after check-in")
      expect(booking.reload.check_in.to_date).to eq(Date.current)
    end
  end

  describe "room actions" do
    it "renders room-status and room-block sheets in the off-canvas frame" do
      get hotel_stay_view_room_status_path(hotel, room_type, "101"), params: { return_to: hotel_stay_view_path(hotel) }, headers: { "Turbo-Frame" => "offcanvas_drawer" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include('turbo-frame id="offcanvas_drawer"', "Change room status", "Physical status")

      get new_hotel_stay_view_room_block_path(hotel), params: {
        room_type_id: room_type.id,
        room_number: "101",
        return_to: hotel_stay_view_path(hotel)
      }, headers: { "Turbo-Frame" => "offcanvas_drawer" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Block room", "Block type", "Room 101")
    end

    it "updates room status and refreshes the board" do
      room_type

      patch hotel_stay_view_room_status_path(hotel, room_type, "101"), params: {
        return_to: hotel_stay_view_path(hotel, view: :rooms, date: Date.current),
        room_status: { status: "cleaning", notes: "In progress" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="stay_view_board"', "Room status updated.")
      expect(hotel.room_statuses.find_by(room_type:, room_number: "101")).to have_attributes(status: "cleaning", notes: "In progress")
    end

    it "creates a room block through the authoritative command" do
      expect {
        post hotel_stay_view_room_blocks_path(hotel), params: {
          return_to: hotel_stay_view_path(hotel),
          room_block: {
            room_type_id: room_type.id,
            room_number: "101",
            start_date: Date.current + 1.day,
            end_date: Date.current + 2.days,
            block_type: "maintenance",
            reason: "Air-conditioning repair"
          }
        }, headers: turbo_headers
      }.to change(RoomBlock, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('target="stay_view_board"', "Room blocked.")
    end

    it "keeps the room-block sheet open with 422 validation errors" do
      post hotel_stay_view_room_blocks_path(hotel), params: {
        return_to: hotel_stay_view_path(hotel),
        room_block: {
          room_type_id: room_type.id,
          room_number: "101",
          start_date: Date.current + 2.days,
          end_date: Date.current,
          block_type: "maintenance",
          reason: ""
        }
      }, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('target="offcanvas_drawer"', "could not be saved")
      expect(RoomBlock).not_to exist(room_number: "101")
    end

    it "blocks room mutations without the required capability" do
      role.role_permissions.joins(:permission).where(permissions: { slug: "manage_room_status" }).delete_all

      patch hotel_stay_view_room_status_path(hotel, room_type, "101"), params: {
        room_status: { status: "cleaning" }
      }

      expect(response).to redirect_to(root_path)
      expect(hotel.room_statuses).not_to exist(room_type:, room_number: "101")
    end

    it "returns 404 for a block owned by another hotel" do
      other_hotel = create(:hotel)
      other_type = create(:room_type, hotel: other_hotel, room_numbers: [ "900" ])
      block = create(:room_block, hotel: other_hotel, room_type: other_type, room_number: "900")

      get edit_hotel_stay_view_room_block_path(hotel, block)

      expect(response).to have_http_status(:not_found)
    end

    it "finishes and removes hotel-scoped blocks with whole-board refreshes" do
      first = create(:room_block, hotel:, room_type:, room_number: "101", start_date: Date.current + 1.day, end_date: Date.current + 2.days)
      second = create(:room_block, hotel:, room_type:, room_number: "102", start_date: Date.current + 3.days, end_date: Date.current + 4.days)

      post finish_hotel_stay_view_room_block_path(hotel, first), params: { return_to: hotel_stay_view_path(hotel) }, headers: turbo_headers
      expect(response).to have_http_status(:success)
      expect(first.reload.completed_at).to be_present

      expect {
        delete hotel_stay_view_room_block_path(hotel, second), params: { return_to: hotel_stay_view_path(hotel) }, headers: turbo_headers
      }.to change(RoomBlock, :count).by(-1)
      expect(response.body).to include('target="stay_view_board"', "Room block removed.")
    end
  end
end
