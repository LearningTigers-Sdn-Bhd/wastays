# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public::Bookings", type: :request do
  let(:hotel) { create(:hotel, name: "Luxury Resort", city: "Malacca", country: "Malaysia") }
  let(:booking) do
    create(:booking,
           hotel: hotel,
           guest_name: "John Doe",
           guest_email: "john@example.com",
           guest_phone: "+60123456789",
           check_in: Date.current,
           check_out: Date.current + 2.days,
           total_amount: 500.0,
           confirmation_token: "CONF123")
  end

  describe "GET /public/bookings/:id" do
    it "renders the booking show page with correct details" do
      get booking_path(booking.confirmation_token)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Booking Secured")
      expect(response.body).to include("CONF123")
      expect(response.body).to include("Luxury Resort")
      expect(response.body).to include("John Doe")
      expect(response.body).to include("RM 500.00")
      expect(response.body).to include("2 Nights")
    end
  end
end
