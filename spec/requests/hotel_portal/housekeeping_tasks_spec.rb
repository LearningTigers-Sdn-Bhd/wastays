require "rails_helper"

RSpec.describe "Hotel portal housekeeping tasks pages", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:permission) { Permission.find_or_create_by!(slug: "manage_requests") { |record| record.name = "Manage Requests" } }

  before do
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.find_or_create_by!(user: user, role: role)
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "task_assignment_minibar_log"), enabled: true)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/housekeeping-tasks" do
    it "renders the page successfully and lists housekeeping requests" do
      booking = create(:booking, hotel: hotel, guest_name: "John Doe", confirmation_token: "WS-HK123")
      create(
        :housekeeping_request,
        booking: booking,
        request_details: "Clean the sheets",
        status: "pending",
        room_number: "101"
      )

      get hotel_housekeeping_tasks_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Housekeeping Tasks")
      expect(response.body).to include("Clean the sheets")
      expect(response.body).to include("101")
    end

    it "filters requests by status" do
      booking = create(:booking, hotel: hotel)
      pending_req = create(:housekeeping_request, booking: booking, request_details: "Need water", status: "pending")
      completed_req = create(:housekeeping_request, booking: booking, request_details: "Need broom", status: "completed")

      get hotel_housekeeping_tasks_path(hotel, status: "pending")

      expect(response.body).to include("Need water")
      expect(response.body).not_to include("Need broom")
    end

    it "filters requests by room number" do
      booking = create(:booking, hotel: hotel)
      create(:housekeeping_request, booking: booking, request_details: "Towels", room_number: "202")
      create(:housekeeping_request, booking: booking, request_details: "Soap", room_number: "303")

      get hotel_housekeeping_tasks_path(hotel, room_number: "202")

      expect(response.body).to include("Towels")
      expect(response.body).not_to include("Soap")
    end
  end
end
