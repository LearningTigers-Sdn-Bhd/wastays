require "rails_helper"

RSpec.describe "Hotel portal housekeeping tasks pages", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:permission) { Permission.find_or_create_by!(slug: "manage_requests") { |record| record.name = "Manage Requests" } }
  let!(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101", "202", "303" ]) }

  before do
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.find_or_create_by!(user: user, role: role)
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "task_assignment_minibar_log"), enabled: true)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/housekeeping-tasks" do
    it "renders the page successfully and lists in_progress housekeeping requests" do
      booking = create(:booking, hotel: hotel, guest_name: "John Doe", confirmation_token: "WS-HK123")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(
        :housekeeping_request,
        booking: booking,
        request_details: "Clean the sheets",
        status: "in_progress",
        room_number: "101"
      )

      get hotel_housekeeping_tasks_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Housekeeping Tasks")
      expect(response.body).to include("Clean the sheets")
      expect(response.body).to include("101")
    end

    it "only shows in_progress requests and excludes other statuses" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:housekeeping_request, booking: booking, request_details: "Need water", status: "in_progress", room_number: "101")
      create(:housekeeping_request, booking: booking, request_details: "Need broom", status: "pending", room_number: "101")
      create(:housekeeping_request, booking: booking, request_details: "Need soap", status: "completed", room_number: "101")

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("Need water")
      expect(response.body).not_to include("Need broom")
      expect(response.body).not_to include("Need soap")
    end

    it "filters requests by room number" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "202")
      create(:housekeeping_request, booking: booking, request_details: "Towels", room_number: "202", status: "in_progress")
      create(:housekeeping_request, booking: booking, request_details: "Soap", room_number: "303", status: "in_progress")

      get hotel_housekeeping_tasks_path(hotel, room_number: "202")

      expect(response.body).to include("Towels")
      expect(response.body).not_to include("Soap")
    end
  end

  describe "PATCH /hotel/:hotel_id/housekeeping_tasks/:id/assign" do
    it "assigns a staff member to the request metadata" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      req = create(:housekeeping_request, booking: booking, status: "in_progress", room_number: "101")
      staff = create(:user, account: account)
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff, hotel: hotel, role: hk_role)
      UserRole.create!(user: staff, role: hk_role)

      patch assign_hotel_housekeeping_task_path(hotel, req), params: { assigned_to: staff.id }

      expect(response).to redirect_to(hotel_room_status_board_path(hotel, tab: "housekeeping"))
      expect(req.reload.metadata["assigned_to"]).to eq(staff.id)
      expect(req.reload.metadata["assigned_to_name"]).to eq(staff.name)
    end
  end

  describe "PATCH /hotel/:hotel_id/requests/housekeeping/:request_id" do
    it "completes the housekeeping request, causing it to disappear and fallback to No Task" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      req = create(:housekeeping_request, booking: booking, status: "in_progress", room_number: "101", request_details: "Clean the window")

      # Verify it's displayed initially
      get hotel_housekeeping_tasks_path(hotel)
      expect(response.body).to include("Clean the window")

      # Update status to completed
      patch hotel_request_status_path(hotel, kind: "housekeeping", request_id: req.id), params: { status: "completed" }

      expect(response).to redirect_to(hotel_requests_path(hotel))
      expect(req.reload.status).to eq("completed")

      # Loading the tasks page again should not show the request, and should display No Task
      get hotel_housekeeping_tasks_path(hotel)
      expect(response.body).not_to include("Clean the window")
      expect(response.body).to include("No Task")
    end
  end
end
