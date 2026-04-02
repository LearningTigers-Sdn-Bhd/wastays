require 'rails_helper'

RSpec.describe "HotelPortal::Bookings::BookingNotes", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:booking) { create(:booking, hotel: hotel) }

  before do
    role = create(:role, account: hotel.account)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "POST /create" do
    it "returns http success" do
      post "/hotel/#{hotel.id}/bookings/#{booking.id}/booking_notes", params: { booking_note: { body: "Note" } }
      expect(response).to have_http_status(:found) # Redirects after create
    end
  end
end
