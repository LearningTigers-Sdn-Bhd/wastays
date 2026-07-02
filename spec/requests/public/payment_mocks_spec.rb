require 'rails_helper'
require 'ostruct'

RSpec.describe "Public::PaymentMocks", type: :request do
  let(:hotel) { create(:hotel) }
  let(:quote) { create(:booking_quote, hotel: hotel) }
  let(:guest_details) do
    {
      name: "Guest",
      email: "guest@example.com",
      phone: "123456",
      government_id: "A123456789",
      gender: "male",
      country: "Malaysia",
      document_type: "passport",
      date_of_birth: "1990-05-20"
    }
  end

  describe "GET /show" do
    it "returns http success" do
      get "/mock_payment", params: { quote_token: quote.token }
      expect(response).to have_http_status(:success)
    end
  end

  describe "POST /update" do
    it "redirects to booking page when confirmation succeeds" do
      booking = create(:booking, booking_quote: quote, hotel: hotel)
      result = OpenStruct.new(success?: true, booking: booking)
      allow(BookingEngine::ConfirmBooking).to receive(:new).and_return(double(call: result))

      post "/mock_payment", params: {
        quote_token: quote.token,
        guest_details: guest_details
      }

      expect(response).to redirect_to(booking_path(booking.confirmation_token))
    end

    it "redirects back to quote page when confirmation fails" do
      result = OpenStruct.new(success?: false, booking: nil, message: "Confirmation failed")
      allow(BookingEngine::ConfirmBooking).to receive(:new).and_return(double(call: result))

      post "/mock_payment", params: {
        quote_token: quote.token,
        guest_details: guest_details
      }

      expect(response).to redirect_to(quote_path(quote.token))
    end
  end
end
