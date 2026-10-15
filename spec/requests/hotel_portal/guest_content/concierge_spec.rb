# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::GuestContent::Concierge", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:concierge_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") do |record|
      record.name = "Manage Hotel Profile"
    end

    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    create(:plan_feature, plan: plan, feature: concierge_feature, enabled: true)
    sign_in_as(user)
  end

  describe "GET the settings page" do
    it "puts Concierge before AI Concierge in Guest Content" do
      get hotel_concierge_settings_path(hotel)

      document = response.parsed_body
      tabs = document.css("[data-testid='settings-tabs'] [data-slot='tabs-trigger']")

      expect(response).to have_http_status(:ok)
      expect(tabs.map { |tab| tab["data-tab-label"] }.last(2)).to eq([ "Concierge", "AI Concierge" ])
      expect(document.at_css("[data-tab-label='Concierge'][aria-current='page']")).to be_present
      expect(document.at_css("[data-testid='guest-content-body'] h2").text.squish).to eq("Concierge Settings")
      expect(document.at_css("[data-testid='guest-content-subtabs']")).to be_nil
    end

    it "renders independent Guest Chat, Refund Requests, and Menu Appearance forms" do
      get hotel_concierge_settings_path(hotel)

      document = response.parsed_body
      forms = document.css("form[action='#{hotel_concierge_settings_path(hotel)}']")

      expect(forms.size).to eq(3)
      expect(forms.map { |form| form.at_css("input[name='section']")["value"] })
        .to eq([ "guest-chat", "refund-requests", "menu-appearance" ])
      expect(forms.first.at_css("input[name='hotel[guest_chat_enabled]']")).to be_present
      expect(forms[1].at_css("input[name='hotel[concierge_refund_requests_enabled]']")).to be_present
      expect(forms.last.css("input[name='hotel[concierge_menu_style]']").map { |input| input["value"] })
        .to eq([ "interactive", "fancy" ])
    end

    it "refuses direct access when the plan excludes Concierge" do
      hotel.plan.plan_features.find_by!(feature: concierge_feature).update!(enabled: false)

      get hotel_concierge_settings_path(hotel)

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("isn't included in your plan")
    end
  end

  describe "PATCH the settings page" do
    it "saves Guest Chat without changing the menu style" do
      patch hotel_concierge_settings_path(hotel), params: {
        section: "guest-chat",
        hotel: { guest_chat_enabled: "0" }
      }

      expect(response).to redirect_to(hotel_concierge_settings_path(hotel))
      expect(hotel.reload.guest_chat_enabled).to be(false)
      expect(hotel.concierge_menu_style).to eq("interactive")
    end

    it "saves Menu Appearance without changing Guest Chat" do
      patch hotel_concierge_settings_path(hotel), params: {
        section: "menu-appearance",
        hotel: { concierge_menu_style: "fancy" }
      }

      expect(response).to redirect_to(hotel_concierge_settings_path(hotel))
      expect(hotel.reload.concierge_menu_style).to eq("fancy")
      expect(hotel.guest_chat_enabled).to be(true)
      expect(hotel.concierge_refund_requests_enabled).to be(false)
    end

    it "saves Refund Requests without changing the other Concierge settings" do
      patch hotel_concierge_settings_path(hotel), params: {
        section: "refund-requests",
        hotel: { concierge_refund_requests_enabled: "1" }
      }

      expect(response).to redirect_to(hotel_concierge_settings_path(hotel))
      expect(hotel.reload.concierge_refund_requests_enabled).to be(true)
      expect(hotel.guest_chat_enabled).to be(true)
      expect(hotel.concierge_menu_style).to eq("interactive")
    end

    it "shows an invalid menu style in the submitted section" do
      patch hotel_concierge_settings_path(hotel), params: {
        section: "menu-appearance",
        hotel: { concierge_menu_style: "plain" }
      }

      document = response.parsed_body
      expect(response).to have_http_status(:unprocessable_content)
      expect(document.at_css("section#menu-appearance .panel-alert")).to be_present
      expect(document.at_css("section#guest-chat .panel-alert")).to be_nil
    end
  end
end
