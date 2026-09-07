# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::GuestContent::AiConcierge", type: :request do
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

  describe "GET the overview" do
    it "opens with a metric row and pairs the readiness list with a questions table" do
      create(:hotel_knowledge_diagnostic, hotel: hotel, question: "Do you allow late check-out?", suggested_category: "policy")

      get hotel_guest_content_path(hotel)

      document = response.parsed_body
      body = document.at_css("[data-testid='guest-content-body']")
      expect(response).to have_http_status(:ok)

      summary = body.at_css("[aria-label='Guest content summary']")
      expect(summary.css(".panel-metric-card__label").map { |label| label.text.squish })
        .to eq([ "Content readiness", "Knowledge documents", "Questions needing answers", "AI Concierge" ])
      expect(summary.at_css(".panel-metric-card__value").text.squish).to eq("0 of 5")

      # The readiness metric card names the left column, so only the right
      # column carries a heading of its own.
      status = body.at_css("[aria-label='Guest content status']")
      expect(status.css("h2").map { |heading| heading.text.squish })
        .to eq([ "Questions needing answers" ])
      expect(status.at_css("[aria-label='Content readiness'] h2")).to be_nil

      table = status.at_css("[data-testid='questions-needing-answers']")
      expect(table.css("thead th").map { |cell| cell.text.squish })
        .to eq([ "Question", "Suggested section", "Asked", "Action" ])
      expect(table.css("tbody tr td").first.text.squish).to eq("Do you allow late check-out?")
    end
  end

  describe "GET the configuration sub-tab" do
    it "renders one page header, the Guest Content tabs, and the AI sub-tabs" do
      get hotel_ai_concierge_settings_path(hotel)

      document = response.parsed_body
      expect(response).to have_http_status(:ok)
      body = document.at_css("[data-testid='guest-content-body']")
      expect(body.css(".panel-page-header").size).to eq(1)
      expect(body.css("h1").map { |heading| heading.text.squish }).to eq([ "Guest Content Settings" ])
      expect(body.css("> div h2").map { |heading| heading.text.squish }).to eq([ "AI Concierge Settings" ])
      expect(document.css("[data-testid='settings-tabs']").size).to eq(1)

      subtabs = document.at_css("[data-testid='guest-content-subtabs']")
      expect(subtabs.css("[data-slot='tabs-trigger']").map { |tab| tab["data-tab-label"] }).to eq([ "Configuration", "Healthcheck" ])
    end

    it "renders AI Concierge as a left-column field stack with Panels UI controls" do
      get hotel_ai_concierge_settings_path(hotel)

      document = response.parsed_body
      form = document.at_css("form[action='#{hotel_ai_concierge_settings_path(hotel)}']")
      section = form.at_css("section")

      expect(form["class"]).to include("gap-4", "lg:grid-cols-2")
      expect(section["class"].to_s).not_to include("lg:col-span-2")
      expect(section.at_css(".space-y-4")).to be_present
      switches = section.css(".panel-switch")
      expect(switches.map { |node| node["data-variant"] }).to eq([ "card", "card" ])
      expect(switches[0].at_css("input[name='hotel[guest_chat_enabled]']")).to be_present
      expect(switches[1].at_css("input[name='hotel[ai_provider_enabled]']")).to be_present
      expect(section.css(".panel-form-field").size).to eq(3)
      expect(section.css(".panel-select-menu").size).to eq(2)
      expect(section.at_css(".panel-input[name='hotel[ai_provider_key]']")).to be_present
      expect(section.at_css("button[type='submit']").text.squish).to eq("Save AI Concierge Configuration")
    end

    it "keeps the AI Concierge tab out of the navigation when the plan excludes it" do
      hotel.plan.plan_features.find_by!(feature: ai_concierge_page_feature).update!(enabled: false)

      get hotel_guest_content_path(hotel)

      tabs = response.parsed_body.at_css("[data-testid='settings-tabs']")
      expect(tabs.css("[data-slot='tabs-trigger']").map { |tab| tab["data-tab-label"] }).not_to include("AI Concierge")
    end
  end

  describe "PATCH the configuration sub-tab" do
    it "updates ai concierge tone and provider configuration" do
      patch hotel_ai_concierge_settings_path(hotel), params: {
        hotel: {
          ai_provider_enabled: "1",
          ai_concierge_tone: "cheerful",
          ai_provider_name: "openai",
          ai_provider_key: "test-api-key"
        }
      }

      expect(response).to redirect_to(hotel_ai_concierge_settings_path(hotel))
      follow_redirect!
      expect(response.body).to include("Settings updated successfully.")

      hotel.reload
      expect(hotel.ai_provider_enabled).to be(true)
      expect(hotel.ai_concierge_tone).to eq("cheerful")
      expect(hotel.ai_provider_name).to eq("openai")
    end

    it "closes the guest chat without touching the ai provider" do
      hotel.update!(ai_provider_enabled: true, ai_provider_name: "openai", ai_provider_key: "test-api-key")

      patch hotel_ai_concierge_settings_path(hotel), params: {
        hotel: {
          guest_chat_enabled: "0",
          ai_provider_enabled: "1",
          ai_concierge_tone: "basic",
          ai_provider_name: "openai",
          ai_provider_key: "test-api-key"
        }
      }

      hotel.reload
      expect(hotel.guest_chat_enabled).to be(false)
      expect(hotel.ai_provider_enabled).to be(true)
    end

    it "keeps the saved API key when the field is left blank" do
      hotel.update!(ai_provider_enabled: true, ai_provider_name: "openai", ai_provider_key: "saved-key")

      patch hotel_ai_concierge_settings_path(hotel), params: {
        hotel: {
          ai_provider_enabled: "1",
          ai_concierge_tone: "basic",
          ai_provider_name: "openai",
          ai_provider_key: ""
        }
      }

      expect(hotel.reload.ai_provider_key).to eq("saved-key")
    end

    it "shows the errors and keeps the page frame when the provider is missing" do
      patch hotel_ai_concierge_settings_path(hotel), params: {
        hotel: {
          ai_provider_enabled: "1",
          ai_concierge_tone: "basic",
          ai_provider_name: "",
          ai_provider_key: ""
        }
      }

      document = response.parsed_body
      expect(response).to have_http_status(:unprocessable_content)
      body = document.at_css("[data-testid='guest-content-body']")
      expect(body.css("h1").map { |heading| heading.text.squish }).to eq([ "Guest Content Settings" ])
      expect(body.css("> div h2").map { |heading| heading.text.squish }).to eq([ "AI Concierge Settings" ])
      expect(document.css("[data-testid='settings-tabs']").size).to eq(1)
      expect(document.at_css("[data-testid='guest-content-subtabs']")).to be_present
      expect(response.body).to include("can&#39;t be blank")
    end

    it "enqueues embeddings for pending documents when the provider is switched on" do
      document = create(:hotel_knowledge_document, hotel: hotel, category: "policy", embedding_status: "pending")

      expect {
        patch hotel_ai_concierge_settings_path(hotel), params: {
          hotel: {
            ai_provider_enabled: "1",
            ai_concierge_tone: "basic",
            ai_provider_name: "openai",
            ai_provider_key: "test-api-key"
          }
        }
      }.to change { document.reload.embedding_status }.from("pending")
    end
  end
end
