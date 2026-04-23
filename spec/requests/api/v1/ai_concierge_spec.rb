require "rails_helper"

RSpec.describe "AI Concierge API", type: :request do
  let(:hotel) { create(:hotel) }
  let(:api_key) { create(:api_key, bearer: hotel) }
  let(:headers) { { "Authorization" => "Bearer #{api_key.token}", "Content-Type" => "application/json" } }
  
  let!(:booking) do
    create(:booking, 
      hotel: hotel, 
      guest_phone: "+60123456789", 
      status: "checked_in",
      check_in: Date.current,
      check_out: Date.current + 2.days
    )
  end
  
  let!(:booking_room) { create(:booking_room, booking: booking, room_number: "101") }

  describe "GET /api/v1/bookings/lookup" do
    it "finds a booking by phone number with fuzzy matching" do
      get "/api/v1/bookings/lookup", params: { phone: "0123456789" }, headers: headers
      
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["id"]).to eq(booking.id)
      expect(json["room_numbers"]).to include("101")
      expect(json["guest_phone"]).to eq(booking.guest_phone)
    end

    it "returns 404 if no active booking is found" do
      get "/api/v1/bookings/lookup", params: { phone: "9999999999" }, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/bookings/:id/housekeeping_requests" do
    it "creates a housekeeping request for the booking" do
      post "/api/v1/bookings/#{booking.id}/housekeeping_requests", 
           params: { housekeeping_request: { request_details: "Need extra towels" } }.to_json,
           headers: headers
      
      expect(response).to have_http_status(:created)
      expect(booking.housekeeping_requests.count).to eq(1)
      expect(booking.housekeeping_requests.first.request_details).to eq("Need extra towels")
    end
  end

  describe "POST /api/v1/bookings/:id/complaint_requests" do
    it "creates a complaint request for the booking" do
      post "/api/v1/bookings/#{booking.id}/complaint_requests", 
           params: { complaint_request: { complaint_details: "AC not cold" } }.to_json,
           headers: headers
      
      expect(response).to have_http_status(:created)
      expect(booking.complaint_requests.count).to eq(1)
      expect(booking.complaint_requests.first.complaint_details).to eq("AC not cold")
    end
  end
end
