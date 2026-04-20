require "rails_helper"

RSpec.describe "Public::Quotes", type: :request do
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
  end
end
