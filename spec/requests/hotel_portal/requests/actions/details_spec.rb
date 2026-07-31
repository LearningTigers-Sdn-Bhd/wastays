require "rails_helper"

RSpec.describe "Request detail sheet", type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:role) { create(:role, account: account, slug: "front_desk", name: "Front Desk") }
  let(:permission) { Permission.find_or_create_by!(slug: "manage_requests") { |record| record.name = "Manage Requests" } }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", guest_name: "Aisyah", confirmation_token: "WS-REQ123") }

  before do
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.find_or_create_by!(user: user, role: role)
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: create(:feature, feature_group: feature_group, slug: "task_assignment_minibar_log"), enabled: true)
    sign_in_as(user)
  end

  def show(kind:, request_id:)
    get hotel_request_action_show_request_path(hotel, kind: kind, request_id: request_id),
        headers: { "Turbo-Frame" => "requests_action_sheet" }
  end

  describe "rendering into the sheet frame" do
    it "renders a housekeeping request" do
      request = create(:housekeeping_request, booking: booking, request_details: "Fresh towels",
                       status: "pending", metadata: { "source" => "concierge_page" })

      show(kind: "housekeeping", request_id: request.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Housekeeping request")
      expect(response.body).to include("Fresh towels")
      expect(response.body).to include("WS-REQ123")
      expect(response.body).to include("Aisyah")
      expect(response.body).to include("Guest, via concierge page")
    end

    it "renders a complaint and its internal notes" do
      request = create(:complaint_request, booking: booking, complaint_details: "Air conditioner noisy",
                       status: "resolved", completed_at: Time.current,
                       internal_notes: [ { "body" => "Maintenance informed" } ])

      show(kind: "complaint", request_id: request.id)

      expect(response.body).to include("Complaint request")
      expect(response.body).to include("Air conditioner noisy")
      expect(response.body).to include("Maintenance informed")
    end

    # A checkout keeps no completed_at, no internal notes and no archived_at.
    it "renders a checkout without the columns a checkout does not have" do
      request = create(:check_out_request, booking: booking, status: "completed", guest_notes: "Leaving early")

      show(kind: "checkout", request_id: request.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Checkout request")
      expect(response.body).to include("Leaving early")
      expect(response.body).to include("No notes recorded.")
    end

    it "falls back to a title when a checkout carries no note" do
      request = create(:check_out_request, booking: booking, status: "pending", guest_notes: nil)

      show(kind: "checkout", request_id: request.id)

      expect(response.body).to include("Checkout requested")
    end

    it "opens itself into the frame that asked for it" do
      request = create(:housekeeping_request, booking: booking, status: "pending")

      show(kind: "housekeeping", request_id: request.id)

      expect(response.body).to include("requests_action_sheet")
      expect(response.body).to include("panels-ui--sheet-frame")
      expect(response.body).to include("<dialog")
    end
  end

  describe "refusing" do
    it "refuses another hotel's request" do
      other_booking = create(:booking, hotel: create(:hotel, account: account))
      request = create(:housekeeping_request, booking: other_booking, status: "pending")

      show(kind: "housekeeping", request_id: request.id)

      expect(response).to redirect_to(hotel_requests_path(hotel))
    end

    it "refuses a request that does not exist" do
      show(kind: "housekeeping", request_id: 0)

      expect(response).to redirect_to(hotel_requests_path(hotel))
    end

    it "refuses a kind it does not serve" do
      show(kind: "minibar", request_id: 1)

      expect(response).to redirect_to(hotel_requests_path(hotel))
    end

    it "refuses a user without manage_requests" do
      RolePermission.where(role: role, permission: permission).destroy_all
      request = create(:housekeeping_request, booking: booking, status: "pending")

      show(kind: "housekeeping", request_id: request.id)

      expect(response).to redirect_to(root_path)
    end
  end

  describe "the pages that launch it" do
    it "gives every board card a launcher and no dialog of its own" do
      create(:housekeeping_request, booking: booking, request_details: "Fresh towels", status: "pending")
      create(:check_out_request, booking: booking, status: "pending", guest_notes: "Leaving early")

      get hotel_requests_path(hotel)
      document = Nokogiri::HTML(response.body)

      expect(document.css('a[data-turbo-frame="requests_action_sheet"]').size).to eq(2)
      # The shell's frame is the only dialog host; no card carries one.
      expect(document.css("turbo-frame#requests_action_sheet dialog")).to be_empty
      expect(document.css("article dialog")).to be_empty
    end

    it "gives every archived card a launcher and no dialog of its own" do
      create(:complaint_request, booking: booking, complaint_details: "Noisy", status: "resolved",
             completed_at: Time.current, archived_at: Time.current)

      get hotel_requests_column_path(hotel, "archived")
      document = Nokogiri::HTML(response.body)

      expect(document.css('a[data-turbo-frame="requests_action_sheet"]').size).to eq(1)
      expect(document.css("article dialog")).to be_empty
    end
  end
end
