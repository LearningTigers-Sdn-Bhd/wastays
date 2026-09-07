require "rails_helper"

RSpec.describe "HotelPortal::NearbyAttractions", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: "admin") }
  let(:hotel_maps_url) { "https://www.google.com/maps/place/Test+Hotel/@5.9800,116.0700,15z" }
  let(:hotel) { create(:hotel, account: account, status: "live", google_map_link: hotel_maps_url) }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }
  let(:attraction_maps_url) { "https://www.google.com/maps/place/Batu+Caves/@5.9850,116.0750,15z" }

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") do |record|
      record.name = "Manage Hotel Profile"
    end
    RolePermission.find_or_create_by!(role: role, permission: permission)
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "GET /hotel/:hotel_id/settings/property/nearby-attractions" do
    it "shows suggestions and attractions linked to the hotel" do
      linked = create(:attraction, name: "Signal Hill", shared_summary: "A city viewpoint.")
      create(:hotel_nearby_attraction, hotel: hotel, attraction: linked, description: "Visit before sunset.")
      rejected = create(:attraction, :rejected, review_note: "The place is permanently closed.")
      create(:hotel_nearby_attraction, hotel: hotel, attraction: rejected)
      suggested = create(
        :attraction,
        name: "Sabah State Museum",
        shared_summary: "Learn about Sabah.",
        latitude: 5.981,
        longitude: 116.071
      )

      get hotel_nearby_attractions_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      expect(document.at_css("h2#nearby-attractions-heading").text.squish).to eq("Nearby Attractions")
      expect(document.at_css("#nearby_attractions_suggestions").text).to include(suggested.name)
      expect(document.at_css("#nearby_attractions_list").text).to include(
        linked.name,
        "Visit before sunset.",
        "Needs attention",
        "The place is permanently closed."
      )
      expect(document.at_css("#nearby_attractions_list").text).not_to include("Pending", "Approved", "Rejected")
      expect(document.css(".panel-button").map { |button| button.text.squish }).to include("Add attraction")
      expect(document.at_css(".panel-table caption.sr-only").text.squish).to eq("Attractions added to this hotel")
      expect(document.at_css("nav.panel-pagination")).to be_nil
    end

    it "opens the suggestions section and counts the list on the toggle" do
      create_list(:attraction, 3, latitude: 5.981, longitude: 116.071)

      get hotel_nearby_attractions_path(hotel)

      document = response.parsed_body
      section = document.at_css("#nearby_attraction_suggestions")
      expect(section["data-state"]).to eq("open")
      expect(section.at_css(".panel-collapsible__trigger").text.squish).to include("Show list (3)", "Hide list (3)")
      expect(section.at_css(".panel-collapsible__content")["hidden"]).to be_nil
    end

    it "collapses the suggestions section when the list is full" do
      create_list(:attraction, 10, latitude: 5.981, longitude: 116.071)

      get hotel_nearby_attractions_path(hotel)

      section = response.parsed_body.at_css("#nearby_attraction_suggestions")
      expect(section["data-state"]).to eq("closed")
      expect(section.at_css(".panel-collapsible__trigger").text.squish).to include("Show list (10)")
      expect(section.at_css(".panel-collapsible__content")["hidden"]).to be_present
    end

    it "disables the suggestions toggle when nothing is left to suggest" do
      get hotel_nearby_attractions_path(hotel)

      section = response.parsed_body.at_css("#nearby_attraction_suggestions")
      trigger = section.at_css(".panel-collapsible__trigger")
      expect(section["data-state"]).to eq("closed")
      expect(trigger["disabled"]).to be_present
      expect(trigger.text.squish).to eq("No more suggestions")
      expect(section.at_css(".panel-collapsible__content")["hidden"]).to be_present
    end

    it "paginates linked attractions at 25 records" do
      create_list(:hotel_nearby_attraction, 26, hotel: hotel)

      get hotel_nearby_attractions_path(hotel)

      document = response.parsed_body
      pagination = document.at_css('#nearby_attractions_list nav.panel-pagination[aria-label="Pagination"]')
      expect(document.at_css("table.panel-table").css("tbody tr").size).to eq(25)
      expect(pagination).to be_present
      expect(pagination.at_css('a[aria-label="Page 2"]')).to be_present

      get hotel_nearby_attractions_path(hotel), params: { page: 2 }

      document = response.parsed_body
      expect(document.at_css("table.panel-table").css("tbody tr").size).to eq(1)
      expect(document.at_css('nav.panel-pagination [aria-current="page"]').text).to eq("2")
    end

    it "shows hotel coordinate guidance without hiding added attractions" do
      hotel.update!(google_map_link: nil)
      linked = create(:attraction, :legacy, name: "Legacy Place")
      create(:hotel_nearby_attraction, hotel: hotel, attraction: linked)

      get hotel_nearby_attractions_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Hotel coordinates are not available.", "Legacy Place")
    end
  end

  describe "POST /hotel/:hotel_id/settings/property/nearby-attractions/preview" do
    it "shows parsed place data for a valid URL" do
      post preview_hotel_nearby_attractions_path(hotel), params: {
        attraction: { google_maps_url: attraction_maps_url }
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Review Nearby Attraction", "Batu Caves", "Create and add")
      expect(response.body).to include("5.98500", "116.07500")
    end

    it "identifies an existing attraction" do
      create(
        :attraction,
        name: "Batu Caves",
        latitude: 5.985,
        longitude: 116.075,
        google_maps_url: attraction_maps_url
      )

      post preview_hotel_nearby_attractions_path(hotel), params: {
        attraction: { google_maps_url: attraction_maps_url }
      }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("This place is ready to add to your hotel.", "Add to hotel")
    end

    it "retains an invalid URL and shows a field error" do
      post preview_hotel_nearby_attractions_path(hotel), params: {
        attraction: { google_maps_url: "https://maps.app.goo.gl/example" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Enter a full Google Maps browser URL.")
      expect(response.body).to include("https://maps.app.goo.gl/example")
    end
  end

  describe "POST /hotel/:hotel_id/settings/property/nearby-attractions" do
    it "creates a pending attraction and links it to the hotel" do
      expect {
        post hotel_nearby_attractions_path(hotel), params: {
          attraction: { google_maps_url: attraction_maps_url }
        }
      }.to change(Attraction, :count).by(1)
        .and change(HotelNearbyAttraction, :count).by(1)

      attraction = Attraction.order(:id).last
      expect(response).to redirect_to(hotel_nearby_attractions_path(hotel))
      expect(attraction).to have_attributes(name: "Batu Caves", status: "pending", source_hotel: hotel, submitted_by: user)
      expect(hotel.hotel_nearby_attractions.last.attraction).to eq(attraction)
    end

    it "reuses an approved registry attraction" do
      attraction = create(
        :attraction,
        name: "Batu Caves",
        latitude: 5.985,
        longitude: 116.075,
        google_maps_url: attraction_maps_url
      )

      expect {
        post hotel_nearby_attractions_path(hotel), params: {
          attraction: { google_maps_url: attraction_maps_url }
        }
      }.not_to change(Attraction, :count)

      expect(hotel.hotel_nearby_attractions.last.attraction).to eq(attraction)
    end

    it "refreshes both page sections and closes the sheet for Turbo" do
      create_list(:hotel_nearby_attraction, 25, hotel: hotel)

      post hotel_nearby_attractions_path(hotel), as: :turbo_stream, params: {
        attraction: { google_maps_url: attraction_maps_url }
      }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include('action="replace" target="nearby_attractions_suggestions"')
      expect(response.body).to include('action="replace" target="nearby_attractions_list"')
      expect(response.body).to include('action="update" target="nearby_attraction_form"')
      expect(response.body).to include("Attraction added to your hotel.")
      expect(response.body).to include("panel-pagination")
    end
  end

  describe "PATCH /hotel/:hotel_id/settings/property/nearby-attractions/:id" do
    it "updates only the hotel guest description" do
      attraction = create(:attraction, shared_summary: "Shared text")
      link = create(:hotel_nearby_attraction, hotel: hotel, attraction: attraction)

      patch hotel_nearby_attraction_path(hotel, link), params: {
        hotel_nearby_attraction: { description: "Hotel-specific guest text" }
      }

      expect(response).to redirect_to(hotel_nearby_attractions_path(hotel))
      expect(link.reload.description).to eq("Hotel-specific guest text")
      expect(attraction.reload.shared_summary).to eq("Shared text")
    end
  end

  describe "DELETE /hotel/:hotel_id/settings/property/nearby-attractions/:id" do
    it "removes the hotel link without deleting the registry attraction" do
      attraction = create(:attraction)
      link = create(:hotel_nearby_attraction, hotel: hotel, attraction: attraction)

      expect {
        delete hotel_nearby_attraction_path(hotel, link)
      }.to change(HotelNearbyAttraction, :count).by(-1)
        .and change(Attraction, :count).by(0)

      expect(response).to redirect_to(hotel_nearby_attractions_path(hotel))
    end
  end
end
