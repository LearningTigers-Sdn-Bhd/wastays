require "rails_helper"

RSpec.describe "Hotel portal housekeeping tasks pages", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:permission) { Permission.find_or_create_by!(slug: "manage_housekeeping_tasks") { |record| record.name = "Manage Housekeeping Tasks" } }
  let(:requests_permission) { Permission.find_or_create_by!(slug: "manage_requests") { |record| record.name = "Manage Requests" } }
  let!(:room_type) { create(:room_type, hotel: hotel, room_number_mode: "custom", room_numbers: [ "101", "202", "303" ]) }

  before do
    RolePermission.find_or_create_by!(role: role, permission: permission)
    RolePermission.find_or_create_by!(role: role, permission: requests_permission)
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

    it "filters requests by room number via query parameter" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "202")
      create(:housekeeping_request, booking: booking, request_details: "Towels", room_number: "202", status: "in_progress")
      create(:housekeeping_request, booking: booking, request_details: "Soap", room_number: "303", status: "in_progress")

      get hotel_housekeeping_tasks_path(hotel, q: "202")

      expect(response.body).to include("Towels")
      expect(response.body).not_to include("Soap")
    end

    it "filters requests by assignee" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      staff1 = create(:user, account: account)
      staff2 = create(:user, account: account)
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff1, hotel: hotel, role: hk_role)
      UserHotelAccess.create!(user: staff2, hotel: hotel, role: hk_role)

      req1 = create(:housekeeping_request, booking: booking, room_number: "101", status: "in_progress", metadata: { "assigned_to" => staff1.id, "assigned_to_name" => staff1.name }, request_details: "Sheets")
      req2 = create(:housekeeping_request, booking: booking, room_number: "202", status: "in_progress", metadata: { "assigned_to" => staff2.id, "assigned_to_name" => staff2.name }, request_details: "Trash")

      get hotel_housekeeping_tasks_path(hotel, assigned_to: staff1.id)

      expect(response.body).to include("Sheets")
      expect(response.body).not_to include("Trash")
    end

    it "filters requests by room status" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "202")

      create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")
      create(:room_status, hotel: hotel, room_type: room_type, room_number: "202", status: "ready")

      create(:housekeeping_request, booking: booking, room_number: "101", status: "in_progress", request_details: "Sheets")
      create(:housekeeping_request, booking: booking, room_number: "202", status: "in_progress", request_details: "Trash")

      get hotel_housekeeping_tasks_path(hotel, room_status: "dirty")

      expect(response.body).to include("Sheets")
      expect(response.body).not_to include("Trash")
    end

    it "resolves active booking for that day but does not filter housekeeping requests by date" do
      booking1 = create(:booking, hotel: hotel, check_in: Date.tomorrow.beginning_of_day, check_out: (Date.tomorrow + 2.days).end_of_day, guest_name: "Alice Smith")
      create(:booking_room, booking: booking1, room_type: room_type, room_number: "101")

      booking2 = create(:booking, hotel: hotel, check_in: Date.current.beginning_of_day, check_out: Date.tomorrow.end_of_day, guest_name: "Bob Jones")
      create(:booking_room, booking: booking2, room_type: room_type, room_number: "202")

      create(:housekeeping_request, booking: booking1, room_number: "101", status: "in_progress", request_details: "Sheets", requested_at: Date.tomorrow)
      create(:housekeeping_request, booking: booking2, room_number: "202", status: "in_progress", request_details: "Trash", requested_at: 2.days.ago)

      get hotel_housekeeping_tasks_path(hotel, date: Date.tomorrow.to_s)

      expect(response.body).to include("101")
      expect(response.body).to include("Alice Smith")
      expect(response.body).to include("Sheets")
      expect(response.body).to include("Trash")
    end

    it "exports housekeeping tasks report to PDF format" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:housekeeping_request, booking: booking, room_number: "101", status: "in_progress", request_details: "Need water")

      get hotel_housekeeping_tasks_path(hotel, format: :pdf)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/pdf")
      expect(response.body).to be_present
    end

    it "exports housekeeping tasks report to XLS format" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:housekeeping_request, booking: booking, room_number: "101", status: "in_progress", request_details: "Need water")

      get hotel_housekeeping_tasks_path(hotel, format: :xls)

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/vnd.ms-excel")
      expect(response.body).to include("Housekeeping Tasks")
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

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      expect(req.reload.metadata["assigned_to"]).to eq(staff.id)
      expect(req.reload.metadata["assigned_to_name"]).to eq(staff.name)
      expect(req.reload.metadata["assignment_history"]).to be_present

      history_entry = req.reload.metadata["assignment_history"].last
      expect(history_entry["assigned_to_id"]).to eq(staff.id)
      expect(history_entry["assigned_to_name"]).to eq(staff.name)
      expect(history_entry["assigned_by_id"]).to eq(user.id)
      expect(history_entry["assigned_by_name"]).to eq(user.name)
      expect(history_entry["timestamp"]).to be_present
    end
  end

  describe "checkout room cleaning rows" do
    it "shows checkout requests with assign and status dropdowns" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      create(:check_out_request, booking: booking, status: "pending", guest_notes: "Checkout Room Cleaning", metadata: { "room_number" => "101" })

      get hotel_housekeeping_tasks_path(hotel)

      expect(response.body).to include("Checkout Room Cleaning")
      expect(response.body).to include(hotel_assign_checkout_request_path(hotel, booking.check_out_requests.first))
      expect(response.body).to include(hotel_checkout_request_status_path(hotel, booking.check_out_requests.first))
      expect(response.body).to include("New")
      expect(response.body).to include("Assigned")
      expect(response.body).to include("In Progress")
      expect(response.body).to include("Completed")
    end

    it "assigns checkout requests and advances the workflow status" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      request = create(:check_out_request, booking: booking, status: "pending", guest_notes: "Checkout Room Cleaning", metadata: { "room_number" => "101" })
      staff = create(:user, account: account)
      hk_role = create(:role, account: account, slug: "housekeeper", name: "Housekeeper")
      UserHotelAccess.create!(user: staff, hotel: hotel, role: hk_role)
      UserRole.create!(user: staff, role: hk_role)

      patch hotel_assign_checkout_request_path(hotel, request), params: { assigned_to: staff.id }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      expect(request.reload.status).to eq("assigned")
      expect(request.metadata["assigned_to"]).to eq(staff.id)
      expect(request.metadata["assigned_to_name"]).to eq(staff.name)
      expect(request.metadata["workflow_status"]).to eq("assigned")
    end

    it "updates checkout requests through the checkout status route" do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
      request = create(:check_out_request, booking: booking, status: "pending", guest_notes: "Checkout Room Cleaning", metadata: { "room_number" => "101" })

      patch hotel_checkout_request_status_path(hotel, request), params: { status: "in_progress" }

      expect(response).to redirect_to(hotel_housekeeping_tasks_path(hotel))
      expect(request.reload.status).to eq("in_progress")
      expect(request.metadata["workflow_status"]).to eq("in_progress")
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
