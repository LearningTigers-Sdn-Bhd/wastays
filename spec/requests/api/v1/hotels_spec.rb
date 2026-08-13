require 'rails_helper'

RSpec.describe "Api::V1::Hotels", type: :request do
  let!(:account) { Account.create!(name: "Test Account", status: "active") }
  let!(:hotel_1) { Hotel.create!(sell_mode: "per_room", account: account, name: "Hotel Alpha", city: "KL", country: "Malaysia", status: "live") }
  let!(:hotel_2) { Hotel.create!(sell_mode: "per_room", account: account, name: "Hotel Beta", city: "Penang", country: "Malaysia", status: "live") }

  let!(:superadmin_key) { ApiKey.create!(name: "Global Key") }
  let!(:hotel_1_key) { ApiKey.create!(name: "Alpha Key", bearer: hotel_1) }

  describe "Authentication" do
    it "returns 401 if no API key is provided" do
      get api_v1_hotels_path
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 if invalid API key is provided" do
      get api_v1_hotels_path, headers: { "Authorization" => "Bearer invalid_token" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "Scoping & Authorization" do
    context "with Superadmin Key" do
      it "can see all hotels" do
        get api_v1_hotels_path, headers: { "Authorization" => "Bearer #{superadmin_key.token}" }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json.count).to be >= 2
      end
    end

    context "with Hotel Restricted Key" do
      it "can only see its own hotel in the list" do
        get api_v1_hotels_path, headers: { "Authorization" => "Bearer #{hotel_1_key.token}" }
        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json.count).to eq(1)
        expect(json.first["name"]).to eq("Hotel Alpha")
      end

      it "returns 403 when trying to access another hotel directly" do
        get api_v1_hotel_path(hotel_2), headers: { "Authorization" => "Bearer #{hotel_1_key.token}" }
        expect(response).to have_http_status(:forbidden)
      end

      it "can access its own hotel directly" do
        get api_v1_hotel_path(hotel_1), headers: { "Authorization" => "Bearer #{hotel_1_key.token}" }
        expect(response).to have_http_status(:ok)
      end
    end
  end
end
