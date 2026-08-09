# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::RoomTypes", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:photo) { fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg") }

  before do
    # Simple auth mock
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(HotelPortal::BaseController).to receive(:current_hotel).and_return(hotel)

    # Mock Pundit
    allow_any_instance_of(HotelPortal::RoomTypesController).to receive(:authorize).and_return(true)

    room_type.photos.attach(photo)
  end

  describe "GET #index" do
    let!(:room_group) { create(:room_group, hotel: hotel) }
    let!(:grouped_room_type) { create(:room_type, hotel: hotel, room_group: room_group) }
    let!(:ungrouped_room_type) { create(:room_type, hotel: hotel, room_group: nil) }

    it "lists rooms as default-open inventory rows with their rate plans" do
      custom_plan = create(:rate_plan, :custom, hotel: hotel, name: "Non-refundable")
      custom_assignment = create(
        :room_type_rate_plan,
        room_type: grouped_room_type,
        rate_plan: custom_plan,
        pricing_mode: "multiplier",
        pricing_value: -10
      )

      get hotel_room_types_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      expect(document.css("h1").map { |heading| heading.text.squish }).to eq([ "Property Details Settings" ])
      expect(document.at_css("h2#room-inventory-heading").text.squish).to eq("Room Inventory")
      expect(document.at_css("[aria-label='Room categories and rate plans']")).to be_present
      expect(document.at_css("#room-inventory-#{grouped_room_type.id}")["data-state"]).to eq("open")
      expect(document.at_css("#room-inventory-rate-plan-#{custom_assignment.id}").text.squish).to include("Non-refundable")
      expect(document.at_css("a[aria-label='Detach Non-refundable from #{grouped_room_type.name}']")).to be_present
      expect(document.at_css("a[aria-label='Create rate plan for #{grouped_room_type.name}']")["href"]).to eq(
        new_hotel_rate_plan_path(hotel, room_type_id: grouped_room_type.id)
      )
      expect(document.at_css("a[aria-label='Attach rate plan to #{grouped_room_type.name}']")["href"]).to eq(
        new_hotel_rate_plan_attachment_path(hotel, room_type_id: grouped_room_type.id)
      )
      expect(document.at_css("body").text).to include("Quantity", "Standard Rate")
      expect(document.css(".dropdown-menu-root").count).to be >= 2
      expect(document.css("button[data-turbo-confirm-tone='destructive']").count).to be >= 2
      expect(document.at_css("body").text).not_to include("Total Categories")
    end

    it "filters by room group id" do
      get hotel_room_types_path(hotel), params: { room_group_id: room_group.id }
      expect(response).to have_http_status(:ok)
    end

    it "filters by unassigned room group" do
      get hotel_room_types_path(hotel), params: { room_group_id: "unassigned" }
      expect(response).to have_http_status(:ok)
    end

    it "falls back to the All tab for an unknown room group" do
      get hotel_room_types_path(hotel), params: { room_group_id: "missing" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.at_css("#room-group-filter-tab-all")[:"aria-current"]).to eq("page")
    end

    it "renders the room group filter tab navigation when room groups exist" do
      get hotel_room_types_path(hotel)
      expect(response.parsed_body.at_css("nav[aria-label='Room Group Filter']")).to be_present
      expect(response.body).not_to include("Unassigned (")
    end

    context "when there are no room groups" do
      before do
        hotel.room_groups.destroy_all
      end

      it "does not render the room group filter tab navigation" do
        get hotel_room_types_path(hotel)
        expect(response.body).not_to include('aria-label="Room Group Filter"')
      end
    end
  end

  describe "GET #new" do
    it "renders the flattened form as a sheet, with every section on one surface" do
      get new_hotel_room_type_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("new-room-category-sheet")
      expect(response.body).to include('data-panels-ui--sheet-dismissible-value="false"')
      %w[basics capacity amenities restrictions numbering photos].each do |section|
        expect(response.body).to include("room-category-#{section}-heading")
      end
      expect(response.body).not_to include('data-panels-ui--tabs-target="tab"')
    end
  end

  describe "POST #create" do
    let(:valid_params) do
      { room_type: { name: "Deluxe Twin", max_adults: 2, max_children: 1, quantity: 3, base_price: 250, room_number_mode: "range" } }
    end

    it "closes the sheet and returns to the list" do
      expect {
        post hotel_room_types_path(hotel), params: valid_params, as: :turbo_stream
      }.to change(RoomType, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="settings_action_sheet"')
      expect(response.body).to include(hotel_room_types_path(hotel))
    end

    it "re-renders the sheet with the errors when the category is invalid" do
      post hotel_room_types_path(hotel), params: { room_type: valid_params[:room_type].merge(name: "") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("new-room-category-sheet")
      expect(response.body).to include("Name can&#39;t be blank")
    end
  end

  describe "PATCH #update" do
    it "closes the sheet and returns to the list" do
      patch hotel_room_type_path(hotel, room_type),
            params: { room_type: { name: "Renamed Category" } },
            as: :turbo_stream

      expect(room_type.reload.name).to eq("Renamed Category")
      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).to include('target="settings_action_sheet"')
    end

    it "re-renders the sheet with the errors when the category is invalid" do
      patch hotel_room_type_path(hotel, room_type), params: { room_type: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("edit-room-category-#{room_type.id}-form")
      expect(response.body).to include("Name can&#39;t be blank")
    end
  end

  describe "DELETE #destroy_photo" do
    let(:photo_attachment) { room_type.photos.first }

    it "deletes a photo and replaces only the photo grid" do
      expect {
        delete destroy_photo_hotel_room_type_path(hotel, room_type, photo_id: photo_attachment.id), as: :turbo_stream
      }.to change { room_type.photos.count }.by(-1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('target="room-type-photos-manager"')
      expect(response.body).to include("Selected photos deleted successfully.")
      # The surrounding form must not be re-rendered, or unsaved edits are lost.
      expect(response.body).not_to include("room-category-basics-heading")
    end

    it "redirects to the list for a non-Turbo request" do
      delete destroy_photo_hotel_room_type_path(hotel, room_type, photo_id: photo_attachment.id)

      expect(response).to redirect_to(hotel_room_types_path(hotel))
      expect(flash[:notice]).to eq("Selected photos deleted successfully.")
    end
  end

  describe "DELETE #bulk_destroy_photos" do
    before do
      room_type.photos.attach(fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg"))
    end

    it "deletes multiple photos and replaces only the photo grid" do
      photo_ids = room_type.photos.pluck(:id)

      expect {
        delete bulk_destroy_photos_hotel_room_type_path(hotel, room_type), params: { photo_ids: photo_ids }, as: :turbo_stream
      }.to change { room_type.photos.count }.to(0)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('target="room-type-photos-manager"')
      expect(response.body).to include("Selected photos deleted successfully.")
    end

    it "reports back into the sheet when no photos were selected" do
      delete bulk_destroy_photos_hotel_room_type_path(hotel, room_type), params: { photo_ids: [] }, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("No photos selected.")
    end
  end
end
