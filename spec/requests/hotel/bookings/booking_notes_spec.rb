require 'rails_helper'

RSpec.describe "Hotel::Bookings::BookingNotes", type: :request do
  describe "GET /create" do
    it "returns http success" do
      get "/hotel/bookings/booking_notes/create"
      expect(response).to have_http_status(:success)
    end
  end

end
