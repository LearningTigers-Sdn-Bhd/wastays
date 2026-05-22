require "rails_helper"

RSpec.describe "Public::Concierge::CheckOuts", type: :request do
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true) }
  let(:booking) { create(:booking, hotel: hotel, guest_name: "Ahmad Zulkifli", status: "checked_in", checked_in_at: Time.current) }

  before { Rails.cache.clear }

  describe "GET /concierge/:hotel_slug/check-out" do
    it "renders the lookup form when no cookie" do
      get concierge_check_out_path(hotel.slug)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Confirmation Code")
    end
  end

  describe "POST /concierge/:hotel_slug/check-out" do
    it "redirects to submit stage after confirmation lookup" do
      post concierge_create_check_out_path(hotel.slug), params: {
        confirmation_token: booking.confirmation_token,
        stage: "lookup"
      }

      expect(response).to redirect_to(concierge_check_out_path(hotel.slug, stage: "submit"))

      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Your Booking")
      expect(response.body).to include("Confirm Checkout Request")
    end

    it "creates a checkout request and shows success on submit stage" do
      expect {
        post concierge_create_check_out_path(hotel.slug), params: {
          confirmation_token: booking.confirmation_token,
          stage: "submit"
        }
      }.to change(CheckOutRequest, :count).by(1)
      expect(response).to redirect_to(concierge_check_out_success_path(hotel.slug))
    end

    it "blocks lookup stage for non-checked-in booking" do
      booking.update!(status: "confirmed")

      post concierge_create_check_out_path(hotel.slug), params: {
        confirmation_token: booking.confirmation_token,
        stage: "lookup"
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Checkout can only be requested for checked-in bookings.")
    end

    it "fails for a non-checked-in booking" do
      booking.update!(status: "confirmed")
      post concierge_create_check_out_path(hotel.slug), params: {
        confirmation_token: booking.confirmation_token,
        stage: "submit"
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "fails on unknown token" do
      post concierge_create_check_out_path(hotel.slug), params: {
        confirmation_token: "WS-XXXXXXXX",
        stage: "lookup"
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "re-renders the form when no booking can be resolved" do
      post concierge_create_check_out_path(hotel.slug)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Confirmation code is required.")
    end
  end
end
