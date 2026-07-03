# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::RoomGroups", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account) }
  let!(:room_group) { create(:room_group, hotel: hotel) }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(HotelPortal::BaseController).to receive(:current_hotel).and_return(hotel)
    allow_any_instance_of(HotelPortal::RoomGroupsController).to receive(:authorize).and_return(true)
  end

  describe "GET #index" do
    it "renders the list successfully" do
      get hotel_room_groups_path(hotel)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST #create" do
    it "creates a new room group with valid parameters" do
      expect {
        post hotel_room_groups_path(hotel), params: { room_group: { name: "New Wing" } }
      }.to change(RoomGroup, :count).by(1)

      expect(response).to redirect_to(hotel_room_groups_path(hotel))
      expect(flash[:notice]).to eq("Room group created successfully.")
    end

    it "renders index with unprocessable_content when parameters are invalid" do
      expect {
        post hotel_room_groups_path(hotel), params: { room_group: { name: "" } }
      }.not_to change(RoomGroup, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET #edit" do
    it "renders the edit page successfully" do
      get edit_hotel_room_group_path(hotel, room_group)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "PATCH #update" do
    it "updates the room group name with valid parameters" do
      patch hotel_room_group_path(hotel, room_group), params: { room_group: { name: "Updated Wing" } }
      expect(room_group.reload.name).to eq("Updated Wing")
      expect(response).to redirect_to(hotel_room_groups_path(hotel))
      expect(flash[:notice]).to eq("Room group updated successfully.")
    end

    it "renders edit with unprocessable_content when parameters are invalid" do
      patch hotel_room_group_path(hotel, room_group), params: { room_group: { name: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "DELETE #destroy" do
    it "deletes the room group and redirects" do
      expect {
        delete hotel_room_group_path(hotel, room_group)
      }.to change(RoomGroup, :count).by(-1)

      expect(response).to redirect_to(hotel_room_groups_path(hotel))
      expect(flash[:notice]).to eq("Room group deleted successfully.")
    end
  end
end
