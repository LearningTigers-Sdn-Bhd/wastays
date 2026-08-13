# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::Concierge::Contact", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan, address: "123 Main St", city: "Kuala Lumpur", country: "Malaysia", whatsapp_number: "60123456789") }

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
  end

  describe "GET /concierge/:hotel_slug/contact" do
    it "returns http success and shows contact links" do
      get "/concierge/#{hotel.slug}/contact"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("wa.me/60123456789")
      expect(response.body).to include("google.com/maps")
    end
  end
end
