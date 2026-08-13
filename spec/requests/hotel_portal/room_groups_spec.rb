# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::RoomGroups", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account) }
  let!(:room_group) { create(:room_group, hotel: hotel, name: "Main Tower") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(HotelPortal::BaseController).to receive(:current_hotel).and_return(hotel)
    allow_any_instance_of(HotelPortal::RoomGroupsController).to receive(:authorize).and_return(true)
  end

  describe "GET #index" do
    it "renders a settings table with CRUD actions and assigned categories" do
      room_type = create(:room_type, hotel: hotel, room_group: room_group, name: "Deluxe Suite")

      get hotel_room_groups_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      table = document.at_css("[data-testid='room-groups-table']")
      expect(table).to be_present
      expect(table.css("thead th").map { |header| header.text.squish }).to eq(
        [ "Room group", "Room categories", "Assigned", "Actions" ]
      )
      row = table.at_css("#room-group-row-#{room_group.id}")
      expect(row.text.squish).to include(room_group.name, room_type.name, "1 category")
      expect(document.at_css("a[href='#{new_hotel_room_group_path(hotel)}']")).to be_present
      expect(row.at_css("a[href='#{edit_hotel_room_group_path(hotel, room_group)}']")).to be_present
      expect(row.at_css("a[aria-label='Delete Main Tower']")).to be_present
    end
  end

  describe "GET #new and #edit" do
    it "renders focused sheets" do
      get new_hotel_room_group_path(hotel)
      expect(response.parsed_body.at_css("#new-room-group-sheet")).to be_present

      get edit_hotel_room_group_path(hotel, room_group)
      expect(response.parsed_body.at_css("#edit-room-group-sheet")).to be_present
    end
  end

  describe "POST #create" do
    it "creates a group and completes the sheet" do
      expect {
        post hotel_room_groups_path(hotel), params: { room_group: { name: "Garden Wing" } }, as: :turbo_stream
      }.to change(RoomGroup, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="complete_sheet"', hotel_room_groups_path(hotel))
    end

    it "re-renders the create sheet when invalid" do
      post hotel_room_groups_path(hotel), params: { room_group: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("new-room-group-sheet", "can&#39;t be blank")
    end
  end

  describe "PATCH #update" do
    it "renames the group without changing membership" do
      room_type = create(:room_type, hotel: hotel, room_group: room_group)

      patch hotel_room_group_path(hotel, room_group),
            params: { room_group: { name: "Renamed Tower" } },
            as: :turbo_stream

      expect(room_group.reload.name).to eq("Renamed Tower")
      expect(room_type.reload.room_group).to eq(room_group)
      expect(response.body).to include('action="complete_sheet"')
    end
  end

  describe "DELETE #destroy" do
    it "deletes the group and leaves its categories unassigned" do
      room_type = create(:room_type, hotel: hotel, room_group: room_group)

      expect {
        delete hotel_room_group_path(hotel, room_group)
      }.to change(RoomGroup, :count).by(-1)

      expect(room_type.reload.room_group).to be_nil
      expect(response).to redirect_to(hotel_room_groups_path(hotel))
    end
  end

  it "permanently redirects the former room-groups URL" do
    get hotel_legacy_room_groups_path(hotel)

    expect(response).to redirect_to(hotel_room_groups_path(hotel))
    expect(response).to have_http_status(:moved_permanently)
  end
end
