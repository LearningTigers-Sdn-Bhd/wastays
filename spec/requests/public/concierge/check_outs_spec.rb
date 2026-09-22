require "rails_helper"

RSpec.describe "Public::Concierge::CheckOuts", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Ahmad Zulkifli", status: "checked_in", checked_in_at: Time.current) }

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
    Rails.cache.clear
  end

  describe "GET /concierge/:hotel_slug/check-out" do
    it "renders the lookup form when no cookie" do
      get concierge_check_out_path(hotel.unique_id, hotel.public_id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Confirmation Code")
    end

    # One responsive template now serves both. The concierge is reached by
    # scanning a QR code in the room, so a page that depends on how a user
    # agent string is read is a page most guests see the wrong half of.
    it "serves the same page to phones and desktops" do
      bodies = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      ].map do |user_agent|
        get concierge_check_out_path(hotel.unique_id, hotel.public_id), headers: { "HTTP_USER_AGENT" => user_agent }
        response.body
      end

      expect(bodies.first).to eq(bodies.last)
    end
  end

  describe "POST /concierge/:hotel_slug/check-out" do
    it "redirects to submit stage after confirmation lookup" do
      post concierge_create_check_out_path(hotel.unique_id, hotel.public_id), params: {
        confirmation_token: booking.confirmation_token,
        stage: "lookup"
      }

      expect(response).to redirect_to(concierge_check_out_path(hotel.unique_id, hotel.public_id, stage: "submit"))

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your Booking")
      expect(response.body).to include("Confirm Checkout Request")
    end

    it "creates a checkout request and shows success on submit stage" do
      expect {
        post concierge_create_check_out_path(hotel.unique_id, hotel.public_id), params: {
          confirmation_token: booking.confirmation_token,
          stage: "submit"
        }
      }.to change(CheckOutRequest, :count).by(1)
      expect(response).to redirect_to(concierge_check_out_success_path(hotel.unique_id, hotel.public_id))
    end

    it "blocks lookup stage for non-checked-in booking" do
      confirmed = create(:booking, hotel: hotel, guest_name: "Ahmad Zulkifli", status: "confirmed")

      post concierge_create_check_out_path(hotel.unique_id, hotel.public_id), params: {
        confirmation_token: confirmed.confirmation_token,
        stage: "lookup"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Checkout can only be requested for checked-in bookings.")
    end

    it "fails for a non-checked-in booking" do
      confirmed = create(:booking, hotel: hotel, guest_name: "Ahmad Zulkifli", status: "confirmed")
      post concierge_create_check_out_path(hotel.unique_id, hotel.public_id), params: {
        confirmation_token: confirmed.confirmation_token,
        stage: "submit"
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "fails on unknown token" do
      post concierge_create_check_out_path(hotel.unique_id, hotel.public_id), params: {
        confirmation_token: "WS-XXXXXXXX",
        stage: "lookup"
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "re-renders the form when no booking can be resolved" do
      post concierge_create_check_out_path(hotel.unique_id, hotel.public_id)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Confirmation code is required.")
    end
  end
end
