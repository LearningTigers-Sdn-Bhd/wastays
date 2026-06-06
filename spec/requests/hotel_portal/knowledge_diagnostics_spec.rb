# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::KnowledgeDiagnostics", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") do |record|
      record.name = "Manage Hotel Profile"
    end

    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/knowledge_diagnostics" do
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

    it "renders diagnostics under the Knowledge group" do
      get hotel_knowledge_diagnostics_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Knowledge Diagnostics")
      expect(response.body).to include("Do you have airport pickup?")
      expect(response.body).to include("Transport")
      expect(response.body).to include("Policy Management")
      expect(response.body).to include("FAQs Management")
      expect(response.body).to include("General Info")
    end

    it "filters by status, answer mode, suggested category, and date range" do
      get hotel_knowledge_diagnostics_path(hotel),
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
      other_hotel = create(:hotel, account: account, status: "approved")
      other_diagnostic = create(:hotel_knowledge_diagnostic, hotel: other_hotel, question: "Other hotel question")

      get hotel_knowledge_diagnostics_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(other_diagnostic.question)
    end

    it "rejects diagnostics for inaccessible hotels" do
      other_hotel = create(:hotel, status: "approved")
      create(:hotel_knowledge_diagnostic, hotel: other_hotel, question: "Private question")

      get hotel_knowledge_diagnostics_path(other_hotel)

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("Private question")
    end
  end

  describe "PATCH /hotel/:hotel_id/knowledge_diagnostics/:id" do
    let!(:diagnostic) { create(:hotel_knowledge_diagnostic, hotel: hotel, diagnostic_status: "open") }

    it "updates diagnostic status" do
      patch hotel_knowledge_diagnostic_path(hotel, diagnostic),
        params: { hotel_knowledge_diagnostic: { diagnostic_status: "reviewed" } }

      expect(response).to redirect_to(hotel_knowledge_diagnostics_path(hotel))
      expect(diagnostic.reload.diagnostic_status).to eq("reviewed")
    end

    it "rejects invalid statuses" do
      patch hotel_knowledge_diagnostic_path(hotel, diagnostic),
        params: { hotel_knowledge_diagnostic: { diagnostic_status: "invalid" } }

      expect(response).to redirect_to(hotel_knowledge_diagnostics_path(hotel))
      expect(diagnostic.reload.diagnostic_status).to eq("open")
    end
  end
end
