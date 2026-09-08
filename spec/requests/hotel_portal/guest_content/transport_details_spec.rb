# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::GuestContent::TransportDetails", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, account: account, status: "live", plan: plan) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") do |record|
      record.name = "Manage Hotel Profile"
    end

    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET the page" do
    it "shows the three sections, each with its own Edit link" do
      get hotel_guest_transport_details_path(hotel)

      expect(response).to have_http_status(:ok)
      headings = response.parsed_body.css("h2").map { |heading| heading.text.squish }
      expect(headings).to include("Directions", "Transportation", "Parking")

      HotelTransportDetail::SECTIONS.each do |section|
        expect(response.body).to include(hotel_edit_guest_transport_detail_path(hotel, section))
      end
    end

    it "works before the hotel has a record, and marks every section Not set" do
      get hotel_guest_transport_details_path(hotel)

      expect(hotel.reload.transport_detail).to be_nil
      expect(response.body.scan("Not set").count).to be_positive
    end

    it "reads the saved numbers back with their units" do
      create(:hotel_transport_detail, :with_parking, :with_transfer, hotel: hotel)

      get hotel_guest_transport_details_path(hotel)

      expect(response.body).to include("45 min")
      expect(response.body).to include("32 km")
      expect(response.body).to include("2.1 m")
      expect(response.body).to include("24 hours")
    end

    it "puts Getting Around on the Hotel Info sub-tabs" do
      get hotel_guest_transport_details_path(hotel)

      expect(response.body).to include("Getting Around")
      expect(response.body).to include(hotel_guest_arrival_departure_path(hotel))
    end
  end

  describe "GET a sheet" do
    it "opens each section on its own" do
      HotelTransportDetail::SECTIONS.each do |section|
        get hotel_edit_guest_transport_detail_path(hotel, section)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(hotel_guest_transport_detail_path(hotel, section))
      end
    end

    it "refuses a section the page does not own" do
      get "/hotel/#{hotel.to_param}/settings/guest-content/general-info/getting-around/helicopter/edit"

      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "PATCH a section" do
    it "creates the record on the first save" do
      patch hotel_guest_transport_detail_path(hotel, "directions"), params: {
        hotel_transport_detail: {
          airport_distance_km: 32,
          airport_travel_minutes: 45,
          directions: "Take exit 14 from the coastal highway."
        }
      }

      expect(response).to redirect_to(hotel_guest_transport_details_path(hotel))
      detail = hotel.reload.transport_detail
      expect(detail.airport_distance_km).to eq(32)
      expect(detail.directions).to eq("Take exit 14 from the coastal highway.")
    end

    it "writes only the columns of the section that was open" do
      create(:hotel_transport_detail, :with_parking, hotel: hotel)

      patch hotel_guest_transport_detail_path(hotel, "directions"), params: {
        hotel_transport_detail: { airport_travel_minutes: 20, parking_price: 999 }
      }

      detail = hotel.reload.transport_detail
      expect(detail.airport_travel_minutes).to eq(20)
      expect(detail.parking_price).to eq(25.00)
    end

    it "saves the parking numbers a guest asks for" do
      patch hotel_guest_transport_detail_path(hotel, "parking"), params: {
        hotel_transport_detail: {
          parking_availability: "on_site",
          parking_type: "valet",
          parking_price: "25.00",
          parking_price_unit: "night",
          parking_spaces: 40,
          parking_height_limit_m: "2.10",
          parking_ev_charging: "1",
          parking_booking_required: "0"
        }
      }

      detail = hotel.reload.transport_detail
      expect(detail.parking_label).to eq("On-site")
      expect(detail.parking_price).to eq(25.00)
      expect(detail.parking_height_limit_m).to eq(2.10)
      expect(detail).to be_parking_ev_charging
      expect(detail).not_to be_parking_booking_required
    end

    it "shows the sheet again when a number is wrong" do
      patch hotel_guest_transport_detail_path(hotel, "parking"), params: {
        hotel_transport_detail: { parking_availability: "on_site", parking_price: -5 }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Parking could not be saved")
      expect(hotel.reload.transport_detail).to be_nil
    end
  end

  describe "another hotel" do
    it "keeps the page inside the hotel the user can manage" do
      other_hotel = create(:hotel, account: create(:account), status: "live", plan: plan)

      get hotel_guest_transport_details_path(other_hotel)

      expect(response).not_to have_http_status(:ok)
    end
  end
end
