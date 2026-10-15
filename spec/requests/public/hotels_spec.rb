require 'rails_helper'

RSpec.describe "Public::Hotels", type: :request do
  let(:hotel) { create(:hotel, status: 'live') }
  let(:easy_plan) { create(:plan, slug: "easy", name: "Easy") }

  describe "GET /index" do
    it "returns http success" do
      get "/hotels"
      expect(response).to have_http_status(:success)
    end

    it "links see options with today's default dates" do
      hotel = create(:hotel, status: "live", name: "Sunset Inn", city: "Kota Kinabalu", country: "Malaysia")
      create(:room_type, hotel: hotel, max_adults: 2)

      availability_service = instance_double(BookingEngine::AvailabilityService)
      allow(BookingEngine::AvailabilityService).to receive(:new).and_return(availability_service)
      allow(availability_service).to receive(:find_available_hotels).and_return([ hotel ])
      allow(availability_service).to receive(:available_rooms_for_hotel).with(hotel).and_return([ hotel.room_types.first ])
      allow(availability_service).to receive(:calculate_total_price).and_return(180)

      get "/hotels", params: { city: "Kota Kinabalu" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("See Options")
      expect(response.body).to include(%(href="/hotels/#{hotel.unique_id}/#{hotel.public_id}?))
      today = Time.use_zone(User::DEFAULT_TIME_ZONE) { Date.current }
      expect(response.body).to include("check_in=#{today}")
      expect(response.body).to include("check_out=#{today + 1.day}")
    end

    it "does not render easy plan hotels in public listing" do
      easy_hotel = create(:hotel, status: "live", name: "Easy Hidden", city: "Kota Kinabalu", country: "Malaysia", plan: easy_plan)
      visible_hotel = create(:hotel, status: "live", name: "Visible Stay", city: "Kota Kinabalu", country: "Malaysia")
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
      get "/hotels/#{hotel.unique_id}/#{hotel.public_id}"
      expect(response).to have_http_status(:success)
    end

    it "shows linked active attractions in a card below Location" do
      hotel.update!(google_map_link: "https://www.google.com/maps/place/Hotel/@5.98000,116.07000,15z")
      farther = create(:attraction, name: "Farther Place", latitude: 6.05, longitude: 116.07)
      nearest = create(:attraction, :pending, name: "Nearby Place", latitude: 5.985, longitude: 116.07)
      rejected = create(:attraction, :rejected, name: "Rejected Place")
      archived = create(:attraction, :archived, name: "Archived Place")
      create(:hotel_nearby_attraction, hotel: hotel, attraction: farther)
      create(:hotel_nearby_attraction, hotel: hotel, attraction: nearest, description: "Walk there for sunset.")
      create(:hotel_nearby_attraction, hotel: hotel, attraction: rejected)
      create(:hotel_nearby_attraction, hotel: hotel, attraction: archived)

      get hotel_path(hotel.unique_id, hotel.public_id)

      document = response.parsed_body
      card = document.at_css("section[aria-labelledby='nearby-attractions-heading']")
      expect(card).to be_present
      expect(card.css("li").map { |item| item.at_css("a.font-semibold").text.squish }).to eq([ "Nearby Place", "Farther Place" ])
      expect(card.text).to include("Walk there for sunset.", "km")
      expect(card.text).not_to include("Rejected Place", "Archived Place", "Pending")
      expect(card.at_css("a[href='#{nearest.google_maps_url}']").text).to eq("Nearby Place")
      expect(card.at_css("a[href='#{nearest.google_maps_url}'][class*='underline']")).to be_present
      expect(card.text).not_to include("View on Google Maps")
      expect(card.at_css("button")).to be_nil
    end

    it "shows three attractions first and expands to reveal the rest" do
      hotel.update!(google_map_link: "https://www.google.com/maps/place/Hotel/@5.98000,116.07000,15z")
      4.times do |index|
        attraction = create(:attraction, name: "Place #{index + 1}",
          latitude: 5.981 + index * 0.001, longitude: 116.07)
        create(:hotel_nearby_attraction, hotel: hotel, attraction: attraction)
      end

      get hotel_path(hotel.unique_id, hotel.public_id)

      card = response.parsed_body.at_css("section[aria-labelledby='nearby-attractions-heading']")
      expect(card.xpath("./ul/li").size).to eq(3)
      more = card.at_css("button[data-nearby-attractions-target='more']")
      more_footer = card.at_css("div[data-nearby-attractions-target='moreFooter']")
      remaining = card.at_css("ul#nearby-attractions-more")
      fewer = card.at_css("button[data-nearby-attractions-target='fewer']")
      fewer_footer = card.at_css("div[data-nearby-attractions-target='fewerFooter']")
      expect(more.text.squish).to eq("Show 1 more")
      expect(more["aria-expanded"]).to eq("false")
      expect(more_footer["class"]).to include("-mx-6", "border-t")
      expect(more["class"]).to include("w-full", "text-center")
      expect(remaining["class"]).to include("hidden")
      expect(remaining.css("li").map { |item| item.at_css("a.font-semibold").text.squish }).to eq([ "Place 4" ])
      expect(fewer.text.squish).to eq("Show fewer")
      expect(fewer_footer["class"]).to include("hidden", "-mx-6", "border-t")
      expect(fewer["class"]).to include("w-full", "text-center")
      expect(fewer_footer.previous_element).to eq(remaining)
    end

    it "hides the nearby attractions card when the hotel has no visible links" do
      create(:hotel_nearby_attraction, hotel: hotel, attraction: create(:attraction, :archived))

      get hotel_path(hotel.unique_id, hotel.public_id)

      expect(response.parsed_body.at_css("#nearby-attractions-heading")).to be_nil
    end

    it "shows the search bar header with date pill" do
      get "/hotels/#{hotel.unique_id}/#{hotel.public_id}", params: {
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

    it "returns 404 when the public ID belongs to a different hotel code" do
      other = create(:hotel, status: "live")

      get hotel_path(other.unique_id, hotel.public_id)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an unknown public ID" do
      get hotel_path(hotel.unique_id, SecureRandom.uuid)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for an invalid public ID" do
      get "/hotels/#{hotel.unique_id}/not-a-uuid"

      expect(response).to have_http_status(:not_found)
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

      get "/hotels/#{hotel.unique_id}/#{hotel.public_id}", params: {
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

      get "/hotels/#{hotel.unique_id}/#{hotel.public_id}"

      expect(response).to redirect_to(hotels_path)
      expect(flash[:alert]).to eq("Hotel not found")
    end
  end
end
