require "rails_helper"

RSpec.describe "Public::Concierge::Home", type: :request do
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true) }

  describe "GET /h/:hotel_slug/concierge" do
    it "returns 200 for a live hotel with concierge enabled" do
      get concierge_home_path(hotel.slug)
      expect(response).to have_http_status(:ok)
    end

    it "renders all five tiles" do
      get concierge_home_path(hotel.slug)
      expect(response.body).to include("Check In")
      expect(response.body).to include("Check Out")
      expect(response.body).to include("Book a Room")
      expect(response.body).to include("Request")
      expect(response.body).to include("Contact Us")
    end

    it "returns 404 for a suspended hotel" do
      hotel.update!(status: "suspended")
      get concierge_home_path(hotel.slug)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when concierge_enabled is false" do
      hotel.update!(concierge_enabled: false)
      get concierge_home_path(hotel.slug)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an unknown slug" do
      get concierge_home_path("does-not-exist")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /h/:hotel_slug/concierge/book" do
    it "redirects to the public hotel page" do
      get concierge_book_path(hotel.slug)
      expect(response).to redirect_to(hotel_path(hotel.slug))
    end
  end
end
