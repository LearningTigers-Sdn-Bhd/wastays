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

    context "when request is from a mobile browser" do
      let(:mobile_ua) { "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" }

      it "renders the mobile template" do
        get concierge_home_path(hotel.slug), headers: { "HTTP_USER_AGENT" => mobile_ua }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("data-mobile-view")
      end

      it "renders all five action tiles" do
        get concierge_home_path(hotel.slug), headers: { "HTTP_USER_AGENT" => mobile_ua }
        expect(response.body).to include("Check In")
        expect(response.body).to include("Check Out")
        expect(response.body).to include("Booking")
        expect(response.body).to include("Request")
        expect(response.body).to include("Contact Us")
      end

      it "links to correct concierge paths" do
        get concierge_home_path(hotel.slug), headers: { "HTTP_USER_AGENT" => mobile_ua }
        expect(response.body).to include(concierge_check_in_path(hotel.slug))
        expect(response.body).to include(concierge_check_out_path(hotel.slug))
        expect(response.body).to include(concierge_new_request_path(hotel.slug))
        expect(response.body).to include(concierge_contact_path(hotel.slug))
      end
    end

    context "when request is from a desktop browser" do
      let(:desktop_ua) { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" }

      it "renders the desktop template" do
        get concierge_home_path(hotel.slug), headers: { "HTTP_USER_AGENT" => desktop_ua }
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("data-mobile-view")
      end
    end
  end

  describe "GET /h/:hotel_slug/concierge/book" do
    it "redirects to the public hotel page" do
      get concierge_book_path(hotel.slug)
      expect(response).to redirect_to(hotel_path(hotel.slug))
    end
  end
end
