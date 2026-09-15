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
      get "/concierge/#{hotel.unique_id}/#{hotel.public_id}/contact"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("wa.me/60123456789")
      expect(response.body).to include("google.com/maps")
    end

    it "shows no front desk badge for a hotel that never filled the page" do
      get "/concierge/#{hotel.unique_id}/#{hotel.public_id}/contact"

      expect(response.body).not_to include("Front desk is")
    end
  end

  describe "the front desk badge" do
    let(:hotel) do
      create(:hotel, status: "live", concierge_enabled: true, plan: plan,
             time_zone: "Kuala Lumpur", contact_phone: "+60 3 1234 5678")
    end

    before do
      create(:hotel_guest_contact, :with_hours, hotel: hotel,
             duty_manager_phone: "+60 12 987 6543",
             emergency_services_number: "999",
             emergency_instructions: "Call 999 first. Then call the front desk on extension 0.")
    end

    it "says the desk is open and hides the duty manager during the day" do
      travel_to Time.find_zone("Kuala Lumpur").parse("2026-09-08 10:00") do
        get "/concierge/#{hotel.unique_id}/#{hotel.public_id}/contact"
      end

      expect(response.body).to include("Front desk is open until 11:00 PM")
      expect(response.body).not_to include("Duty Manager")
    end

    it "says the desk is closed and offers the duty manager at night" do
      travel_to Time.find_zone("Kuala Lumpur").parse("2026-09-08 03:00") do
        get "/concierge/#{hotel.unique_id}/#{hotel.public_id}/contact"
      end

      expect(response.body).to include("Front desk is closed")
      expect(response.body).to include("Opens again at 7:00 AM")
      expect(response.body).to include("Duty Manager (Urgent Only)")
    end

    it "shows the emergency card at any hour" do
      travel_to Time.find_zone("Kuala Lumpur").parse("2026-09-08 10:00") do
        get "/concierge/#{hotel.unique_id}/#{hotel.public_id}/contact"
      end

      expect(response.body).to include("Police, fire, ambulance")
      expect(response.body).to include("Call 999 first.")
    end
  end
end
