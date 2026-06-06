# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::Concierge::Contact", type: :request do
  let(:hotel) { create(:hotel, status: "approved", address: "123 Main St", city: "Kuala Lumpur", country: "Malaysia", whatsapp_number: "60123456789") }

  describe "GET /concierge/:hotel_slug/contact" do
    it "returns http success and shows contact links" do
      get "/concierge/#{hotel.slug}/contact"

      expect(response).to have_http_status(:success)
      expect(response.body).to include("wa.me/60123456789")
      expect(response.body).to include("google.com/maps")
    end
  end
end
