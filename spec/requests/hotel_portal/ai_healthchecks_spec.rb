# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::GuestContent::AiHealthchecks", type: :request, frozen_time: Time.zone.local(2026, 6, 10, 3) do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") do |record|
      record.name = "Manage Hotel Profile"
    end

    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/settings/guest-content/ai-concierge/healthcheck" do
    let!(:open_diagnostic) do
      create(:hotel_knowledge_diagnostic,
        hotel: hotel,
        question: "Do you have airport pickup?",
        intent: "hotel_information",
        topic: "general_hotel_info",
        answer_mode: "unavailable",
        suggested_category: "general_info",
        knowledge_matches: [
          {
            "document_title" => "Transport",
            "category" => "general_info",
            "content" => "Airport pickup details.",
            "distance" => 0.78
          }
        ],
        best_distance: 0.78)
    end

    let!(:resolved_diagnostic) do
      create(:hotel_knowledge_diagnostic,
        hotel: hotel,
        question: "What is the pool policy?",
        diagnostic_status: "resolved",
        answer_mode: "fallback",
        suggested_category: "policy")
    end

    it "renders the healthcheck sub-tab under AI Concierge" do
      get hotel_ai_healthchecks_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Healthcheck")
      expect(response.body).to include("Do you have airport pickup?")
      expect(response.body).to include("Transport")
      expect(response.body).to include("Policies")
      expect(response.body).to include("FAQs")
      expect(response.body).to include("Hotel Info")
    end

    it "renders the reusable table, metric cards, and badges" do
      get hotel_ai_healthchecks_path(hotel)

      expect(response.body).to include("panel-table")
      expect(response.body).to include("panel-metric-card")
      expect(response.body).to include("panel-badge")
      expect(response.body).not_to include("Filter\"")
    end

    it "puts a single-select filter in each filtered column header" do
      get hotel_ai_healthchecks_path(hotel)

      expect(response.body).to include("status-column-filter")
      expect(response.body).to include("answer-mode-column-filter")
      expect(response.body).to include("suggested-category-column-filter")
    end

    it "shows the reports time period filter and defaults to all time" do
      get hotel_ai_healthchecks_path(hotel)

      expect(response.body).to include("Time period")
      expect(response.body).to include("Do you have airport pickup?")
    end

    it "narrows the list with the time period preset" do
      old_diagnostic = create(:hotel_knowledge_diagnostic, hotel: hotel, question: "Old question")
      old_diagnostic.update_column(:created_at, 2.years.ago)

      get hotel_ai_healthchecks_path(hotel), params: { date_preset: "this_year" }

      expect(response.body).to include("Do you have airport pickup?")
      expect(response.body).not_to include("Old question")
    end

    it "filters by status, answer mode, suggested category, and date range" do
      get hotel_ai_healthchecks_path(hotel),
        params: {
          status: "open",
          answer_mode: "unavailable",
          suggested_category: "general_info",
          start_date: open_diagnostic.created_at.to_date.to_s,
          end_date: open_diagnostic.created_at.to_date.to_s
        }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Do you have airport pickup?")
      expect(response.body).not_to include("What is the pool policy?")
    end

    it "does not expose another hotel's diagnostics" do
      other_hotel = create(:hotel, account: account, status: "live")
      other_diagnostic = create(:hotel_knowledge_diagnostic, hotel: other_hotel, question: "Other hotel question")

      get hotel_ai_healthchecks_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(other_diagnostic.question)
    end

    it "rejects diagnostics for inaccessible hotels" do
      other_hotel = create(:hotel, status: "live")
      create(:hotel_knowledge_diagnostic, hotel: other_hotel, question: "Private question")

      get hotel_ai_healthchecks_path(other_hotel)

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("Private question")
    end

    it "redirects when AI concierge page is excluded from plan" do
      hotel.plan.plan_features.find_by!(feature: ai_concierge_page_feature).update!(enabled: false)

      get hotel_ai_healthchecks_path(hotel)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("This feature isn't included in your plan. Upgrade to access it.")
    end
  end

  describe "GET /hotel/:hotel_id/settings/guest-content/ai-concierge/healthcheck/:id" do
    let!(:diagnostic) do
      create(:hotel_knowledge_diagnostic,
        hotel: hotel,
        question: "Is there a shuttle?",
        answer: "The hotel runs a shuttle at 08:00.",
        knowledge_matches: [ { "document_title" => "Shuttle", "content" => "Shuttle times." } ])
    end

    it "renders the detail action sheet" do
      get hotel_ai_healthcheck_path(hotel, diagnostic)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("healthcheck-detail-sheet")
      expect(response.body).to include("healthcheck-status-form")
      expect(response.body).to include("Is there a shuttle?")
      expect(response.body).to include("The hotel runs a shuttle at 08:00.")
      expect(response.body).to include("Shuttle")
    end

    it "does not expose another hotel's diagnostic" do
      other_hotel = create(:hotel, account: account, status: "live")
      other_diagnostic = create(:hotel_knowledge_diagnostic, hotel: other_hotel)

      get hotel_ai_healthcheck_path(hotel, other_diagnostic)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /hotel/:hotel_id/settings/guest-content/ai-concierge/healthcheck/:id" do
    let!(:diagnostic) { create(:hotel_knowledge_diagnostic, hotel: hotel, diagnostic_status: "open") }

    it "updates diagnostic status" do
      patch hotel_ai_healthcheck_path(hotel, diagnostic),
        params: { hotel_knowledge_diagnostic: { diagnostic_status: "reviewed" } }

      expect(response).to redirect_to(hotel_ai_healthchecks_path(hotel))
      expect(diagnostic.reload.diagnostic_status).to eq("reviewed")
    end

    it "closes the sheet when the request comes from a turbo frame" do
      patch hotel_ai_healthcheck_path(hotel, diagnostic),
        params: { hotel_knowledge_diagnostic: { diagnostic_status: "resolved" } },
        headers: { "Turbo-Frame" => "settings_action_sheet", "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("complete_sheet")
      expect(diagnostic.reload.diagnostic_status).to eq("resolved")
    end

    it "rejects invalid statuses and keeps the sheet open" do
      patch hotel_ai_healthcheck_path(hotel, diagnostic),
        params: { hotel_knowledge_diagnostic: { diagnostic_status: "invalid" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("The status was not saved")
      expect(diagnostic.reload.diagnostic_status).to eq("open")
    end
  end
end
