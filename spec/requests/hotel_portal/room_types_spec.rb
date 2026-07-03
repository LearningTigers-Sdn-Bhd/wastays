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

    it "lists all room types by default" do
      get hotel_room_types_path(hotel)
      expect(response).to have_http_status(:ok)
    end

    it "filters by room group id" do
      get hotel_room_types_path(hotel), params: { room_group_id: room_group.id }
      expect(response).to have_http_status(:ok)
    end

    it "filters by unassigned room group" do
      get hotel_room_types_path(hotel), params: { room_group_id: "unassigned" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE #destroy_photo" do
    let(:photo_attachment) { room_type.photos.first }

    it "deletes a photo and redirects" do
      expect {
        delete destroy_photo_hotel_room_type_path(hotel, room_type, photo_id: photo_attachment.id)
      }.to change { room_type.photos.count }.by(-1)

      expect(response).to redirect_to(edit_hotel_room_type_path(hotel, room_type))
      expect(flash[:notice]).to eq("Selected photos deleted successfully.")
    end
  end

  describe "DELETE #bulk_destroy_photos" do
    before do
      room_type.photos.attach(fixture_file_upload(Rails.root.join("spec/fixtures/files/sample_image.jpg"), "image/jpeg"))
    end

    it "deletes multiple photos and redirects" do
      photo_ids = room_type.photos.pluck(:id)

      expect {
        delete bulk_destroy_photos_hotel_room_type_path(hotel, room_type), params: { photo_ids: photo_ids }
      }.to change { room_type.photos.count }.to(0)

      expect(response).to redirect_to(edit_hotel_room_type_path(hotel, room_type))
      expect(flash[:notice]).to eq("Selected photos deleted successfully.")
    end

    it "handles no photos selected" do
      delete bulk_destroy_photos_hotel_room_type_path(hotel, room_type), params: { photo_ids: [] }

      expect(response).to redirect_to(edit_hotel_room_type_path(hotel, room_type))
      expect(flash[:alert]).to eq("No photos selected.")
    end
  end
end
