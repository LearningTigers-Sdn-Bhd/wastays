# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Attractions", type: :request do
  let(:account) { create(:account) }
  let(:superadmin) { create(:user, :superadmin, account:) }
  let(:google_maps_url) do
    "https://www.google.com/maps/place/Signal+Hill+Observatory/@5.99020,116.07550,15z"
  end

  before { sign_in_as(superadmin) }

  describe "GET /admin/attractions" do
    it "renders status tabs, the desktop table, and mobile cards" do
      create(:attraction, name: "Signal Hill Observatory")

      get admin_attractions_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Attraction Registry", "Pending", "Approved", "Archived")
      expect(response.body).to include("Attractions matching the current filters", "Signal Hill Observatory")
      expect(response.body).to include("md:hidden")
    end

    it "filters attractions by status" do
      create(:attraction, :pending, name: "Pending Place")
      create(:attraction, name: "Approved Place")

      get admin_attractions_path(status: "pending")

      expect(response.body).to include("Pending Place")
      expect(response.body).not_to include("Approved Place")
    end

    it "searches by a linked hotel name" do
      hotel = create(:hotel, name: "Harbour View Hotel")
      match = create(:attraction, name: "Waterfront Market")
      create(:hotel_nearby_attraction, hotel:, attraction: match)
      create(:attraction, name: "Mountain Garden")

      get admin_attractions_path(q: "Harbour View")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Waterfront Market")
      expect(response.body).not_to include("Mountain Garden")
    end

    it "paginates filtered results with Pagy and preserves the filters" do
      create_list(:attraction, 26, name: "Shared Park", status: :approved)

      get admin_attractions_path, params: { status: "approved", q: "Shared Park" }

      navigation = Nokogiri::HTML(response.body).at_css("nav.panel-pagination")
      second_page = navigation.at_css('a[aria-label="Page 2"]')

      expect(second_page["href"]).to include("page=2", "q=Shared+Park", "status=approved")
      expect(second_page["data-turbo-action"]).to eq("advance")
    end
  end

  describe "the Google Maps URL flow" do
    it "previews a valid URL without creating a record" do
      expect {
        post preview_admin_attractions_path, params: { attraction: { google_maps_url: } }
      }.not_to change(Attraction, :count)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Detected attraction", "Signal Hill Observatory", "5.99020", "116.07550")
    end

    it "retains an invalid URL and shows the parser error" do
      invalid_url = "https://maps.app.goo.gl/short-link"

      post preview_admin_attractions_path, params: { attraction: { google_maps_url: invalid_url } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(invalid_url, "Enter a full Google Maps browser URL")
    end

    it "creates and approves a parsed attraction" do
      expect {
        post admin_attractions_path, params: { attraction: { google_maps_url: } }
      }.to change(Attraction, :count).by(1)

      attraction = Attraction.order(:id).last
      expect(attraction).to have_attributes(
        name: "Signal Hill Observatory",
        status: "approved",
        submitted_by: superadmin,
        reviewed_by: superadmin
      )
      expect(response).to redirect_to(admin_attractions_path)
    end

    it "approves and reuses a duplicate instead of creating another record" do
      parsed = Attractions::GoogleMapsUrlParser.call(google_maps_url).parsed
      existing = create(
        :attraction,
        :rejected,
        name: parsed.name,
        latitude: parsed.latitude,
        longitude: parsed.longitude,
        coordinate_fingerprint: parsed.fingerprint
      )

      expect {
        post admin_attractions_path, params: { attraction: { google_maps_url: } }
      }.not_to change(Attraction, :count)

      expect(existing.reload).to be_status_approved
    end
  end

  describe "GET /admin/attractions/:id/edit" do
    it "shows source information and possible duplicates" do
      hotel = create(:hotel, name: "Source Hotel")
      attraction = create(:attraction, :pending, source_hotel: hotel, name: "City Museum")
      create(
        :attraction,
        name: "City Museum Annex",
        latitude: attraction.latitude + BigDecimal("0.001"),
        longitude: attraction.longitude + BigDecimal("0.001")
      )

      get edit_admin_attraction_path(attraction)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Review attraction", "Source Hotel", "Possible duplicates", "City Museum Annex")
    end
  end

  describe "PATCH /admin/attractions/:id" do
    it "updates shared registry fields" do
      attraction = create(:attraction)

      patch admin_attraction_path(attraction), params: {
        attraction: { name: "Updated Place", shared_summary: "A shared summary.", city: "Kota Kinabalu" }
      }

      expect(response).to redirect_to(admin_attractions_path)
      expect(attraction.reload).to have_attributes(
        name: "Updated Place",
        shared_summary: "A shared summary.",
        city: "Kota Kinabalu"
      )
    end
  end

  describe "review actions" do
    it "approves a pending attraction" do
      attraction = create(:attraction, :pending)

      patch approve_admin_attraction_path(attraction)

      expect(attraction.reload).to be_status_approved
      expect(attraction.reviewed_by).to eq(superadmin)
    end

    it "requires a reason before rejection" do
      attraction = create(:attraction, :pending)

      patch reject_admin_attraction_path(attraction), params: { attraction: { review_note: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(attraction.reload).to be_status_pending
      expect(response.body).to include("Review note is required")
    end

    it "rejects an attraction with a reason" do
      attraction = create(:attraction, :pending)

      patch reject_admin_attraction_path(attraction), params: {
        attraction: { review_note: "The URL points to a business, not an attraction." }
      }

      expect(attraction.reload).to be_status_rejected
      expect(attraction.review_note).to include("not an attraction")
    end

    it "archives and restores the previous status" do
      attraction = create(:attraction, :pending)

      patch archive_admin_attraction_path(attraction)
      expect(attraction.reload).to be_status_archived
      expect(attraction.archived_from_status).to eq("pending")

      patch restore_admin_attraction_path(attraction)
      expect(attraction.reload).to be_status_pending
      expect(attraction.archived_from_status).to be_nil
    end

    it "merges hotel links into the selected target" do
      hotel = create(:hotel)
      source = create(:attraction, name: "Duplicate Place")
      target = create(:attraction, name: "Canonical Place")
      create(:hotel_nearby_attraction, hotel:, attraction: source, description: "Hotel description")

      patch merge_admin_attraction_path(source), params: { merge: { target_id: target.id } }

      expect(response).to redirect_to(admin_attractions_path)
      expect(source.reload).to be_status_archived
      expect(source.merged_into).to eq(target)
      expect(target.hotel_nearby_attractions.find_by(hotel:).description).to eq("Hotel description")
    end
  end
end
