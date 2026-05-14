require 'rails_helper'

RSpec.describe "Public::Hotels", type: :request do
  let(:hotel) { create(:hotel, status: 'approved') }

  describe "GET /index" do
    it "returns http success" do
      get "/hotels"
      expect(response).to have_http_status(:success)
    end

    it "links see options with today's default dates" do
      hotel = create(:hotel, status: "approved", name: "Sunset Inn", city: "Kota Kinabalu", country: "Malaysia")
      create(:room_type, hotel: hotel, max_adults: 2)

      availability_service = instance_double(BookingEngine::AvailabilityService)
      allow(BookingEngine::AvailabilityService).to receive(:new).and_return(availability_service)
      allow(availability_service).to receive(:find_available_hotels).and_return([ hotel ])
      allow(availability_service).to receive(:available_rooms_for_hotel).with(hotel).and_return([ hotel.room_types.first ])
      allow(availability_service).to receive(:calculate_total_price).and_return(180)

      get "/hotels", params: { city: "Kota Kinabalu" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("See Options")
      expect(response.body).to include(%(href="/hotels/#{hotel.slug}?))
      today = Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current }
      expect(response.body).to include("check_in=#{today}")
      expect(response.body).to include("check_out=#{today + 1.day}")
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/hotels/#{hotel.id}"
      expect(response).to have_http_status(:success)
    end

    it "shows the search bar header with date pill" do
      get "/hotels/#{hotel.id}", params: {
        check_in: Date.current.to_s,
        check_out: Date.tomorrow.to_s,
        adults: 2,
        children: 0,
        room_count: 1
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Check-In / Out")
      expect(response.body).to include("rate-calendar")
    end
  end
end
