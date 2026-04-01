require 'rails_helper'

RSpec.describe "HotelPortal::Bookings", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /index" do
    it "returns http success" do
      get "/hotel/bookings"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/hotel/bookings/#{booking.id}"
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /update" do
    it "returns http success" do
      patch "/hotel/bookings/#{booking.id}", params: { booking: { status: "confirmed" } }
      expect(response).to have_http_status(:found)
    end
  end

  describe "POST /check_in" do
    it "updates the booking status to checked_in" do
      post "/hotel/bookings/#{booking.id}/check_in"
      expect(response).to have_http_status(:found)
      expect(booking.reload.status).to eq("checked_in")
      expect(booking.checked_in_at).to be_present
    end
  end

  describe "POST /check_out" do
    it "updates the booking status to completed" do
      booking.update!(status: 'checked_in')
      post "/hotel/bookings/#{booking.id}/check_out"
      expect(response).to have_http_status(:found)
      expect(booking.reload.status).to eq("completed")
      expect(booking.checked_out_at).to be_present
    end
  end

  describe "POST /cancel" do
    it "returns http success" do
      post "/hotel/bookings/#{booking.id}/cancel"
      expect(response).to have_http_status(:found)
    end
  end
end
