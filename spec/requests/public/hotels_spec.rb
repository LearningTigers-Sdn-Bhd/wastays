require 'rails_helper'

RSpec.describe "Public::Hotels", type: :request do
  let(:hotel) { create(:hotel, status: 'approved') }
  let(:easy_plan) { create(:plan, slug: "easy", name: "Easy") }

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

    it "does not render easy plan hotels in public listing" do
      easy_hotel = create(:hotel, status: "approved", name: "Easy Hidden", city: "Kota Kinabalu", country: "Malaysia", plan: easy_plan)
      visible_hotel = create(:hotel, status: "approved", name: "Visible Stay", city: "Kota Kinabalu", country: "Malaysia")
      create(:room_type, hotel: easy_hotel, max_adults: 2)
      create(:room_type, hotel: visible_hotel, max_adults: 2)

      availability_service = instance_double(BookingEngine::AvailabilityService)
      allow(BookingEngine::AvailabilityService).to receive(:new).and_return(availability_service)
      allow(availability_service).to receive(:find_available_hotels).and_return([ easy_hotel, visible_hotel ])
      allow(availability_service).to receive(:available_rooms_for_hotel).with(easy_hotel).and_return([ easy_hotel.room_types.first ])
      allow(availability_service).to receive(:available_rooms_for_hotel).with(visible_hotel).and_return([ visible_hotel.room_types.first ])
      allow(availability_service).to receive(:calculate_total_price).and_return(180)

      get "/hotels", params: { city: "Kota Kinabalu" }

      expect(response.body).to include("Visible Stay")
      expect(response.body).not_to include("Easy Hidden")
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

    it "sorts restricted rooms to the bottom of the list when dates are provided" do
      unrestricted_rt = create(:room_type, hotel: hotel, name: "Unrestricted Deluxe Room", quantity: 5, max_adults: 2, base_price: 100, room_number_mode: "range")
      restricted_rt = create(:room_type, hotel: hotel, name: "Restricted Suite Room", quantity: 5, max_adults: 2, base_price: 150, room_number_mode: "range")

      check_in = Date.current + 1.day
      check_out = check_in + 1.day

      [ unrestricted_rt, restricted_rt ].each do |rt|
        RoomInventory.create!(room_type: rt, date: check_in, quantity: 5, status: "open")
        standard_plan = rt.rate_plans.first
        RoomRate.create!(room_type: rt, rate_plan: nil, date: check_in, price: rt.base_price, currency: "MYR")
        RoomRate.create!(room_type: rt, rate_plan: standard_plan, date: check_in, price: rt.base_price, currency: "MYR")
      end

      RoomRate.where(room_type: restricted_rt, date: check_in).update_all(min_stay: 3)

      get "/hotels/#{hotel.id}", params: {
        check_in: check_in.to_s,
        check_out: check_out.to_s,
        adults: 2,
        children: 0,
        room_count: 1
      }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Unrestricted Deluxe Room")
      expect(response.body).to include("Restricted Suite Room")

      idx_unrestricted = response.body.index("Unrestricted Deluxe Room")
      idx_restricted = response.body.index("Restricted Suite Room")

      expect(idx_unrestricted).to be < idx_restricted
    end

    it "redirects when hotel is on easy plan" do
      hotel.update!(plan: easy_plan)

      get "/hotels/#{hotel.id}"

      expect(response).to redirect_to(hotels_path)
      expect(flash[:alert]).to eq("Hotel not found")
    end
  end
end
