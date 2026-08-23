require "rails_helper"

RSpec.describe "Public::Concierge::Home", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
  end

  describe "GET /h/:hotel_slug/concierge" do
    it "returns 200 for a live hotel with concierge enabled" do
      get concierge_home_path(hotel)
      expect(response).to have_http_status(:ok)
    end

    it "renders all five tiles" do
      get concierge_home_path(hotel)
      expect(response.body).to include("Check In")
      expect(response.body).to include("Check Out")
      expect(response.body).to include("Book a Room")
      expect(response.body).to include("Request")
      expect(response.body).to include("Contact Us")
    end

    it "keeps the page but drops the chat tile when guest chat is off" do
      hotel.update!(guest_chat_enabled: false)

      get concierge_home_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Contact Us")
      expect(response.body).not_to include("Chat With Us")
      expect(response.body).not_to include(concierge_chat_path(hotel))
    end

    it "returns 404 for a suspended hotel" do
      hotel.update!(status: "suspended")
      get concierge_home_path(hotel)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when concierge_enabled is false" do
      hotel.update!(concierge_enabled: false)
      get concierge_home_path(hotel)
      expect(response).to have_http_status(:not_found)
    end

    it "redirects to public hotel page when AI concierge page is excluded from plan" do
      hotel.plan.plan_features.find_by!(feature: ai_concierge_page_feature).update!(enabled: false)

      get concierge_home_path(hotel)

      expect(response).to redirect_to(hotel_path(hotel))
      expect(flash[:alert]).to eq("AI concierge is not available for this hotel.")
    end

    it "returns 404 for an unknown slug" do
      get concierge_home_path("does-not-exist")
      expect(response).to have_http_status(:not_found)
    end

    # The concierge is reached by scanning a QR code in the room, so a tile that
    # only exists on one of the two home templates is a tile most guests never see.
    it "offers the chat on every device" do
      [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      ].each do |user_agent|
        get concierge_home_path(hotel), headers: { "HTTP_USER_AGENT" => user_agent }

        expect(response.body).to include(concierge_chat_path(hotel))
        expect(response.body).to include("Chat With Us")
      end
    end

    context "when request is from a mobile browser" do
      let(:mobile_ua) { "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" }

      it "renders the mobile template" do
        get concierge_home_path(hotel), headers: { "HTTP_USER_AGENT" => mobile_ua }
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("data-mobile-view")
      end

      it "renders all five action tiles" do
        get concierge_home_path(hotel), headers: { "HTTP_USER_AGENT" => mobile_ua }
        expect(response.body).to include("Check In")
        expect(response.body).to include("Check Out")
        expect(response.body).to include("Booking")
        expect(response.body).to include("Request")
        expect(response.body).to include("Contact Us")
      end

      it "links to correct concierge paths" do
        get concierge_home_path(hotel), headers: { "HTTP_USER_AGENT" => mobile_ua }
        expect(response.body).to include(concierge_check_in_path(hotel))
        expect(response.body).to include(concierge_check_out_path(hotel))
        expect(response.body).to include(concierge_new_request_path(hotel))
        expect(response.body).to include(concierge_contact_path(hotel))
      end
    end

    context "when request is from a desktop browser" do
      let(:desktop_ua) { "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36" }

      it "renders the desktop template" do
        get concierge_home_path(hotel), headers: { "HTTP_USER_AGENT" => desktop_ua }
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("data-mobile-view")
      end
    end
  end

  describe "GET /h/:hotel_slug/concierge/book" do
    it "redirects to the public hotel page" do
      get concierge_book_path(hotel)
      expect(response).to redirect_to(hotel_path(hotel))
    end
  end
end
