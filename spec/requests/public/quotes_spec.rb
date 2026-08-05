require "rails_helper"

RSpec.describe "Public::Quotes", type: :request do
  describe "GET /quotes/:token" do
    let(:hotel) { create(:hotel, status: "approved") }
    let(:quote) { create(:booking_quote, hotel: hotel, **snapshot) }

    before { create(:booking_quote_item, booking_quote: quote, room_type: create(:room_type, hotel: hotel)) }

    context "with a structured cancellation policy" do
      let(:snapshot) do
        {
          cancellation_policy_snapshot: "Old prose nobody should see",
          cancellation_policy_snapshot_data: {
            "description" => "Non-refundable during Hari Raya.",
            "refund_processing_days" => 7,
            "refund_method" => "original_payment_method",
            "tiers" => [
              { "days_before_arrival" => 14, "window" => "14+ days before arrival", "charge" => "No charge" },
              { "days_before_arrival" => 0, "window" => "Less than 1 day before arrival", "charge" => "keep 100.00% of total stay" }
            ]
          }
        }
      end

      it "renders the tier table with the hotel's own terms beneath it" do
        get quote_path(quote.token)

        expect(response.body).to include("14+ days before arrival", "No charge", "keep 100.00% of total stay")
        expect(response.body).to include("Refunds are issued to the original payment method within 7 working days.")
        expect(response.body).to include("Non-refundable during Hari Raya.")
        # Prose and table can never be shown together, or they could contradict.
        expect(response.body).not_to include("Old prose nobody should see")
      end
    end

    context "without one" do
      let(:snapshot) { { cancellation_policy_snapshot: "Free cancellation up to 24 hours before arrival" } }

      it "falls back to the legacy prose snapshot" do
        get quote_path(quote.token)

        expect(response.body).to include("Free cancellation up to 24 hours before arrival")
      end
    end
  end

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
      expect(flash[:alert]).to eq("No valid rate for room #{room_type.name} with selected occupancy.")
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
        document_type: "ic",
        date_of_birth: Date.new(1990, 5, 20)
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
        "document_type" => guest.document_type,
        "date_of_birth" => "1990-05-20"
      )
    end

    it "returns found false when email is not matched" do
      get guest_lookup_quote_path(quote.token), params: { email: "new@example.com" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["found"]).to eq(false)
      expect(body["guest_details"]).to eq({})
    end

    it "does not return blacklisted warning when email belongs to blacklisted guest on quote page" do
      Guest.create!(
        name: "Blacklisted Guest",
        email: "banned@example.com",
        phone: "+60123456789",
        government_id: "A999999",
        gender: "male",
        country: "Malaysia",
        document_type: "ic",
        date_of_birth: Date.new(1990, 5, 20),
        blacklisted: true
      )

      get guest_lookup_quote_path(quote.token), params: { email: "banned@example.com" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["blacklisted"]).to be_nil
      expect(body["message"]).to be_nil
      expect(body["found"]).to eq(true)
      expect(body["guest_details"]["name"]).to eq("Blacklisted Guest")
    end

    it "returns validation error when email is blank" do
      get guest_lookup_quote_path(quote.token), params: { email: "  " }

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["found"]).to eq(false)
      expect(body["message"]).to eq("Email is required.")
    end
  end
end
