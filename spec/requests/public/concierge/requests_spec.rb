require "rails_helper"

RSpec.describe "Public::Concierge::Requests", type: :request do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Ahmad Zulkifli", status: "checked_in", checked_in_at: Time.current) }

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
    Rails.cache.clear
  end

  describe "GET /h/:hotel_slug/concierge/requests/new" do
    it "renders the lookup form" do
      get concierge_new_request_path(hotel.unique_id, hotel.public_id)
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
        get concierge_new_request_path(hotel.unique_id, hotel.public_id), headers: { "HTTP_USER_AGENT" => user_agent }
        response.body
      end

      expect(bodies.first).to eq(bodies.last)
    end
  end

  describe "POST /h/:hotel_slug/concierge/requests" do
    it "redirects to submit stage after confirmation lookup" do
      post concierge_requests_path(hotel.unique_id, hotel.public_id), params: {
        confirmation_token: booking.confirmation_token,
        stage: "lookup"
      }

      expect(response).to redirect_to(concierge_new_request_path(hotel.unique_id, hotel.public_id, stage: "submit"))

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your Booking")
      expect(response.body).to include("Submit Request")
    end

    it "creates a housekeeping request and shows success on submit stage" do
      expect {
        post concierge_requests_path(hotel.unique_id, hotel.public_id), params: {
          confirmation_token: booking.confirmation_token,
          stage: "submit",
          kind: "housekeeping",
          details: "Please bring extra towels"
        }
      }.to change(HousekeepingRequest, :count).by(1)
      expect(response).to redirect_to(concierge_request_success_path(hotel.unique_id, hotel.public_id))
    end

    it "blocks lookup stage for completed booking" do
      completed = create(:booking, hotel: hotel, guest_name: "Ahmad Zulkifli", status: "completed")

      post concierge_requests_path(hotel.unique_id, hotel.public_id), params: {
        confirmation_token: completed.confirmation_token,
        stage: "lookup"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("This booking has already been checked out.")
    end

    it "creates a complaint request" do
      expect {
        post concierge_requests_path(hotel.unique_id, hotel.public_id), params: {
          confirmation_token: booking.confirmation_token,
          stage: "submit",
          kind: "complaint",
          details: "AC is not working"
        }
      }.to change(ComplaintRequest, :count).by(1)
    end

    it "tags the request with concierge_page source" do
      post concierge_requests_path(hotel.unique_id, hotel.public_id), params: {
        confirmation_token: booking.confirmation_token,
        stage: "submit",
        kind: "housekeeping",
        details: "Extra pillows please"
      }
      expect(HousekeepingRequest.last.metadata["source"]).to eq("concierge_page")
    end

    it "fails when details are blank" do
      post concierge_requests_path(hotel.unique_id, hotel.public_id), params: {
        confirmation_token: booking.confirmation_token,
        stage: "submit",
        kind: "housekeeping",
        details: ""
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "re-renders the form when no booking can be resolved" do
      post concierge_requests_path(hotel.unique_id, hotel.public_id), params: {
        kind: "housekeeping",
        stage: "submit",
        details: "Extra pillows please"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Confirmation code is required.")
    end

    it "renders a clean success page after a successful submission" do
      post concierge_requests_path(hotel.unique_id, hotel.public_id), params: {
        confirmation_token: booking.confirmation_token,
        stage: "submit",
        kind: "housekeeping",
        details: "Please bring extra towels"
      }

      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body.scan("Our team has been notified.").size).to eq(1)
      expect(response.body).to include("Request Type")
      expect(response.body).to include("Housekeeping")
      expect(response.body).to include("Please bring extra towels")
    end
  end
end
