require "rails_helper"

RSpec.describe "Public::Quotes", type: :request do
  describe "POST /quotes" do
    let!(:account) { create(:account) }
    let!(:hotel) { create(:hotel, account: account, status: "approved") }
    let!(:room_type) { create(:room_type, hotel: hotel, max_adults: 2, quantity: 5, base_price: 100) }
    let!(:rate_plan) { create(:rate_plan, room_type: room_type, name: "2-4 Night Rate", currency: "MYR") }
    let(:check_in) { Date.current }
    let(:check_out) { check_in + 1.day }

    before do
      RoomInventory.create!(room_type: room_type, date: check_in, quantity: 5, status: "open")
      RoomRate.create!(room_type: room_type, date: check_in, price: 100, currency: "MYR")
      RoomRate.create!(
        room_type: room_type,
        rate_plan: rate_plan,
        date: check_in,
        price: 120,
        currency: "MYR",
        min_stay: 2,
        max_stay: 4
      )
    end

    it "rejects quote creation when the selected rate plan violates min/max stay restrictions" do
      post quotes_path, params: {
        hotel_id: hotel.slug,
        room_type_id: room_type.id,
        check_in: check_in,
        check_out: check_out,
        adults: 2,
        rate_plan_id: rate_plan.id
      }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("No valid rate is available for these dates.")
      expect(BookingQuote.count).to eq(0)
    end
  end

  describe "GET /quotes/:id/guest_lookup" do
    let(:quote) { create(:booking_quote) }

    it "returns saved guest details when email exists" do
      guest = Guest.create!(
        name: "John Doe",
        email: "john@example.com",
        phone: "+60123456789",
        government_id: "A1234567",
        gender: "male",
        country: "Malaysia",
        document_type: "ic"
      )

      get guest_lookup_quote_path(quote.token), params: { email: "  JOHN@example.com " }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["found"]).to eq(true)
      expect(body["guest_details"]).to include(
        "name" => guest.name,
        "email" => guest.email,
        "phone" => guest.phone,
        "government_id" => guest.government_id,
        "gender" => guest.gender,
        "country" => guest.country,
        "document_type" => guest.document_type
      )
    end

    it "returns found false when email is not matched" do
      get guest_lookup_quote_path(quote.token), params: { email: "new@example.com" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["found"]).to eq(false)
      expect(body["guest_details"]).to eq({})
    end

    it "returns validation error when email is blank" do
      get guest_lookup_quote_path(quote.token), params: { email: "  " }

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["found"]).to eq(false)
      expect(body["message"]).to eq("Email is required.")
    end

    it "returns restriction_failed true when min stay restriction in snapshot is violated" do
      quote_with_item = create(:booking_quote, check_in: Date.current, check_out: Date.current + 1.day)
      create(:booking_quote_item,
        booking_quote: quote_with_item,
        nightly_rate_snapshot: {
          Date.current.to_s => {
            "min_stay" => 3,
            "max_stay" => nil,
            "price" => 150
          }
        }
      )

      get guest_lookup_quote_path(quote_with_item.token), params: { email: "test@example.com" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["restriction_failed"]).to eq(true)
      expect(body["message"]).to include("minimum stay requirement of 3 night(s)")
    end

    it "returns restriction_failed true when max stay restriction in snapshot is violated" do
      quote_with_item = create(:booking_quote, check_in: Date.current, check_out: Date.current + 4.days)
      create(:booking_quote_item,
        booking_quote: quote_with_item,
        nightly_rate_snapshot: {
          Date.current.to_s => {
            "min_stay" => nil,
            "max_stay" => 2,
            "price" => 150
          }
        }
      )

      get guest_lookup_quote_path(quote_with_item.token), params: { email: "test@example.com" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["restriction_failed"]).to eq(true)
      expect(body["message"]).to include("maximum stay requirement of 2 night(s)")
    end

    it "returns restriction_failed true when database RoomRate has min stay restriction violated" do
      hotel = create(:hotel)
      room_type = create(:room_type, hotel: hotel)
      quote_with_item = create(:booking_quote, hotel: hotel, check_in: Date.current, check_out: Date.current + 1.day)
      create(:booking_quote_item,
        booking_quote: quote_with_item,
        room_type: room_type,
        nightly_rate_snapshot: {
          Date.current.to_s => {
            "rate_plan_id" => nil,
            "price" => 150
          }
        }
      )

      RoomRate.create!(
        room_type: room_type,
        date: Date.current,
        price: 150,
        currency: "MYR",
        rate_plan_id: nil,
        min_stay: 2
      )

      get guest_lookup_quote_path(quote_with_item.token), params: { email: "test@example.com" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["restriction_failed"]).to eq(true)
      expect(body["message"]).to include("minimum stay requirement of 2 night(s)")
    end
  end
end
