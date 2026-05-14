require "rails_helper"

RSpec.describe "Public::Hotels rate_calendar", type: :request do
  let!(:account)   { Account.create!(name: "RC Req", slug: "rc-req", status: "active") }
  let!(:hotel)     { Hotel.create!(name: "RC Hotel", city: "KL", country: "Malaysia", account: account, status: "approved") }
  let!(:room_type) { RoomType.create!(hotel: hotel, name: "Standard", quantity: 5, max_adults: 2, base_price: 100, room_number_mode: "range") }

  let(:today) { Date.current }
  let(:base_params) { { start_date: today.to_s, end_date: (today + 6).to_s } }

  def seed_day(date, price: 200.0, quantity: 5, status: "open")
    RoomRate.create!(room_type: room_type, date: date, price: price, currency: "MYR")
    RoomInventory.create!(room_type: room_type, date: date, quantity: quantity, status: status)
  end

  def json = JSON.parse(response.body)

  describe "GET /hotels/:id/rate_calendar" do
    it "returns 404 for unknown slug" do
      get "/hotels/no-such-hotel/rate_calendar", params: base_params
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when hotel is not active" do
      hotel.update!(status: "draft")
      get "/hotels/#{hotel.slug}/rate_calendar", params: base_params
      expect(response).to have_http_status(:not_found)
    end

    it "returns 422 when end_date < start_date" do
      get "/hotels/#{hotel.slug}/rate_calendar", params: { start_date: today.to_s, end_date: (today - 1).to_s }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "returns 422 when window > 180 days" do
      get "/hotels/#{hotel.slug}/rate_calendar", params: { start_date: today.to_s, end_date: (today + 181).to_s }
      expect(response).to have_http_status(:unprocessable_content)
    end

    context "happy path" do
      before { 7.times { |i| seed_day(today + i) } }

      it "returns 200 with correct day count and prices" do
        get "/hotels/#{hotel.slug}/rate_calendar", params: base_params
        expect(response).to have_http_status(:ok)
        expect(json["days"].length).to eq(7)
        expect(json["days"].first["min_price"]).to eq(200.0)
        expect(json["days"].first["available"]).to be true
        expect(json["days"].first["rooms_left"]).to eq(5)
      end

      it "includes currency and date range" do
        get "/hotels/#{hotel.slug}/rate_calendar", params: base_params
        expect(json["currency"]).to eq("MYR")
        expect(json["start_date"]).to eq(today.iso8601)
        expect(json["end_date"]).to eq((today + 6).iso8601)
      end
    end

    it "marks sold-out day as unavailable (quantity 0)" do
      RoomRate.create!(room_type: room_type, date: today, price: 200, currency: "MYR")
      RoomInventory.create!(room_type: room_type, date: today, quantity: 0, status: "open")
      get "/hotels/#{hotel.slug}/rate_calendar", params: { start_date: today.to_s, end_date: today.to_s }
      day = json["days"].first
      expect(day["available"]).to be false
      expect(day["rooms_left"]).to eq(0)
    end

    it "marks closed inventory as unavailable" do
      seed_day(today, status: "closed")
      get "/hotels/#{hotel.slug}/rate_calendar", params: { start_date: today.to_s, end_date: today.to_s }
      expect(json["days"].first["available"]).to be false
    end

    it "returns MIN price across multiple room types" do
      room_type2 = RoomType.create!(hotel: hotel, name: "Suite", quantity: 2, max_adults: 2, base_price: 500, room_number_mode: "range")
      RoomRate.create!(room_type: room_type, date: today, price: 300, currency: "MYR")
      RoomRate.create!(room_type: room_type2, date: today, price: 150, currency: "MYR")
      RoomInventory.create!(room_type: room_type, date: today, quantity: 5, status: "open")
      RoomInventory.create!(room_type: room_type2, date: today, quantity: 2, status: "open")
      get "/hotels/#{hotel.slug}/rate_calendar", params: { start_date: today.to_s, end_date: today.to_s }
      expect(json["days"].first["min_price"]).to eq(150.0)
    end

    it "excludes nights where inventory < room_count" do
      RoomRate.create!(room_type: room_type, date: today, price: 200, currency: "MYR")
      RoomInventory.create!(room_type: room_type, date: today, quantity: 2, status: "open")
      get "/hotels/#{hotel.slug}/rate_calendar", params: { start_date: today.to_s, end_date: today.to_s, room_count: 3 }
      expect(json["days"].first["available"]).to be false
    end

    it "defaults start_date to today and end_date to +90 when omitted" do
      get "/hotels/#{hotel.slug}/rate_calendar"
      expect(response).to have_http_status(:ok)
      expect(json["days"].length).to eq(91) # today..today+90 inclusive
    end
  end
end
