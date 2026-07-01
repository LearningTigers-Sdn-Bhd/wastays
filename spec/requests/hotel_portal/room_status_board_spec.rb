# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::RoomStatusBoard", type: :request do
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, plan: plan) }
  let(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101" ]) }

  def grant_permission(role, slug)
    permission = Permission.find_by(slug: slug) || create(:permission, slug: slug, name: slug.tr("_", " ").titleize)
    create(:role_permission, role: role, permission: permission)
  end

  def sign_in_with_permissions(*slugs)
    user = create(:user)
    role = create(:role, account: hotel.account)
    slugs.each { |slug| grant_permission(role, slug) }
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "room_status_board"), enabled: true)
    sign_in_as(user)
  end

  def sign_in_with_account_permission(*slugs)
    user = create(:user)
    hotel_role = create(:role, account: hotel.account)
    create(:user_hotel_access, user: user, hotel: hotel, role: hotel_role)

    account_role = create(:role, account: user.account)
    slugs.each { |slug| grant_permission(account_role, slug) }
    create(:user_role, user: user, role: account_role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "room_status_board"), enabled: true)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/room-status" do
    it "responds successfully for users with view_room_readiness permission" do
      sign_in_with_permissions("view_room_readiness")

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
    end

    it "allows account-level view_room_readiness permission alone" do
      sign_in_with_account_permission("view_room_readiness")

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
    end

    it "responds successfully for users with manage_room_status permission" do
      sign_in_with_permissions("manage_room_status")

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
    end

    it "redirects users without room status permissions" do
      user = create(:user)
      create(:user_hotel_access, user: user, hotel: hotel, role: create(:role, account: hotel.account))
      sign_in_as(user)

      get hotel_room_status_board_path(hotel)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("not authorized")
    end

    it "allows account-level room status permissions alone" do
      sign_in_with_account_permission("manage_room_status")

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
    end

    it "renders occupancy block for bookings that start before the selected board window" do
      sign_in_with_permissions("view_room_readiness")
      start_date = Date.new(2026, 5, 7)
      booking = create(
        :booking,
        hotel: hotel,
        status: "checked_in",
        guest_name: "Carryover Guest",
        check_in: start_date - 1.day,
        check_out: start_date + 1.day
      )
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

      get hotel_room_status_board_path(hotel), params: { start_date: start_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Carryover Guest")
    end

    it "renders density controls, legends, and room amenity chips from query params" do
      sign_in_with_permissions("view_room_readiness")
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")
      room_type.update!(smoking_allowed: true, pets_allowed: true)

      get hotel_room_status_board_path(hotel), params: { start_date: Date.current.to_s, days: 7, layout: "compact" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Compact Mode")
      expect(response.body).to include("7 days")
      expect(response.body).to include('title="Previous 7 days"')
      expect(response.body).to include('title="Next 7 days"')
      expect(response.body).to include("Ready")
      expect(response.body).to include("Smoking Allowed")
      expect(response.body).to include("Pets Allowed")
      expect(response.body).to include('id="start_date"')
      expect(response.body).to include('id="days"')
    end

    it "renders correctly with awaiting_inspection status and shows action dropdown" do
      sign_in_with_permissions("view_room_readiness", "manage_room_status")
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "awaiting_inspection")

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Awaiting Inspection")
      expect(response.body).to include("Actions")
      expect(response.body).to include("Send back to cleaning")
      expect(response.body).to include("Ready")
    end

    it "renders correctly with DND active or inactive and shows the toggle button" do
      sign_in_with_permissions("view_room_readiness", "manage_room_status")
      room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty", dnd: false)

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Do Not Disturb")
      expect(response.body).to include("Flag guest requested DND today")

      # Now make DND active
      room_status.update!(dnd: true, dnd_date: hotel.current_business_date)

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Remove DND")
      expect(response.body).to include("Resume cleaning schedules")
    end

    it "renders the late checkout detected action for manageable ready rooms" do
      sign_in_with_permissions("view_room_readiness", "manage_room_status")
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Late Checkout Detected")
      expect(response.body).to include("late_checkout_detected")
    end

    it "renders review due out bookings on the board" do
      sign_in_with_permissions("view_room_readiness", "manage_room_status")
      start_date = Date.new(2026, 6, 10)
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "late_checkout_detected")
      booking = create(
        :booking,
        hotel: hotel,
        status: "checked_in",
        guest_name: "Late Guest",
        check_in: start_date,
        check_out: start_date + 2.days
      )
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      booking.transition_status_to!("review_due_out", event: "detect_late_checkout")

      get hotel_room_status_board_path(hotel), params: { start_date: start_date.to_s }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Late Guest")
      expect(response.body).to include("Review Due Out")
    end

    it "renders status notes in the tooltip when present" do
      sign_in_with_permissions("view_room_readiness")
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "inspection_failed", notes: "Dust on headboard")

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Dust on headboard")
    end

    it "renders correctly with an unknown status using fallback styles" do
      sign_in_with_permissions("view_room_readiness")
      # Bypass validation to create a room status with an unknown status
      rs = build(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "unknown_status")
      rs.save!(validate: false)

      get hotel_room_status_board_path(hotel)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Unknown Status")
      expect(response.body).to include("bg-slate-400")
    end
  end

  describe "GET /hotel/:hotel_id/room-status/housekeeping-requests/:room_number" do
    it "responds successfully for users with view_room_readiness permission" do
      sign_in_with_permissions("view_room_readiness")
      booking = create(:booking, hotel: hotel, status: "checked_in")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:housekeeping_request, booking: booking, status: "in_progress", request_details: "Extra towels")

      get hotel_room_status_housekeeping_requests_path(hotel, "101")

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Extra towels")
      expect(response.body).to include("In progress")
    end
  end
end
