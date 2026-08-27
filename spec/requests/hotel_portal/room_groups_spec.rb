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
    it "shows physical-room counts and represented room categories" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe Suite")
      create(:room, hotel: hotel, room_type: room_type, room_group: room_group, number: "101")
      create(:room, hotel: hotel, room_type: room_type, room_group: room_group, number: "102", archived_at: 1.day.ago)
      create(:room, hotel: hotel, room_type: room_type, number: "103")

      get hotel_room_groups_path(hotel)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      table = document.at_css("[data-testid='room-groups-table']")
      expect(table.css("thead th").map { |header| header.text.squish }).to eq(
        [ "Room group", "Room categories", "Assigned rooms", "Actions" ]
      )
      row = table.at_css("#room-group-row-#{room_group.id}")
      expect(row.text.squish).to include("Main Tower", "Deluxe Suite", "1 room")
      expect(document.text.squish).to include("1 active room unassigned")
      expect(document.at_css("a[href='#{new_hotel_room_group_path(hotel)}']")).to be_present
      expect(row.at_css("a[href='#{edit_hotel_room_group_path(hotel, room_group)}']")).to be_present
      expect(row.at_css("a[aria-label='Delete Main Tower']")).to be_present
    end
  end

  describe "GET #new and #edit" do
    it "shows searchable active rooms and preselects the current members" do
      room_type = create(:room_type, hotel: hotel, name: "Deluxe King")
      selected_room = create(:room, hotel: hotel, room_type: room_type, room_group: room_group, number: "101")
      unassigned_room = create(:room, hotel: hotel, room_type: room_type, number: "102")
      other_group = create(:room_group, hotel: hotel, name: "Garden Wing")
      grouped_elsewhere = create(:room, hotel: hotel, room_type: room_type, room_group: other_group, number: "103")
      archived_room = create(:room, hotel: hotel, room_type: room_type, number: "104", archived_at: 1.day.ago)

      get edit_hotel_room_group_path(hotel, room_group)

      expect(response).to have_http_status(:ok)
      document = response.parsed_body
      sheet = document.at_css("#edit-room-group-sheet")
      expect(sheet["class"].split).to include("w-[48rem]")
      expect(sheet.at_css("input[name='room_group_filters[query]'][type='search']")).to be_present
      expect(sheet.at_css("select[name='room_group_filters[room_type_id]']")).to be_present
      expect(sheet.at_css("[data-testid='room-group-room-list']")).to be_present

      selected = sheet.at_css("input[value='#{selected_room.id}']")
      expect(selected["name"]).to eq("room_group[room_ids][]")
      expect(selected["checked"]).to eq("checked")
      expect(sheet.at_css("input[value='#{unassigned_room.id}']")["checked"]).to be_nil
      expect(sheet.at_css("input[value='#{grouped_elsewhere.id}']")).to be_nil
      expect(sheet.text.squish).to include("Deluxe King · In this group", "Unassigned")
      expect(sheet.text.squish).not_to include("Currently in Garden Wing")
      expect(sheet.at_css("input[value='#{archived_room.id}']")).to be_nil

      get new_hotel_room_group_path(hotel)
      expect(response.parsed_body.at_css("#new-room-group-sheet input[value='#{selected_room.id}']")).to be_nil
    end

    it "shows an empty state when the hotel has no physical rooms" do
      get new_hotel_room_group_path(hotel)

      expect(response.parsed_body.text.squish).to include("No physical rooms are available")
    end
  end

  describe "POST #create" do
    it "creates a group and assigns rooms from multiple categories" do
      first_room = create(:room, hotel: hotel, room_type: create(:room_type, hotel: hotel), number: "101")
      second_room = create(:room, hotel: hotel, room_type: create(:room_type, hotel: hotel), number: "201")

      expect {
        post hotel_room_groups_path(hotel),
             params: { room_group: { name: "Garden Wing", room_ids: [ first_room.id, second_room.id ] } },
             as: :turbo_stream
      }.to change(RoomGroup, :count).by(1)

      created_group = hotel.room_groups.find_by!(name: "Garden Wing")
      expect(created_group.active_rooms).to contain_exactly(first_room, second_room)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="complete_sheet"', hotel_room_groups_path(hotel))
    end

    it "re-renders the sheet with selected rooms when the group is invalid" do
      room = create(:room, hotel: hotel, room_type: create(:room_type, hotel: hotel))

      post hotel_room_groups_path(hotel), params: { room_group: { name: "", room_ids: [ room.id ] } }

      expect(response).to have_http_status(:unprocessable_content)
      document = response.parsed_body
      expect(document.at_css("#new-room-group-sheet input[value='#{room.id}']")["checked"]).to eq("checked")
      expect(response.body).to include("Name can&#39;t be blank")
      expect(room.reload.room_group).to be_nil
    end
  end

  describe "PATCH #update" do
    it "assigns unassigned rooms and unassigns deselected active rooms" do
      room_type = create(:room_type, hotel: hotel)
      removed_room = create(:room, hotel: hotel, room_type: room_type, room_group: room_group, number: "101")
      added_room = create(:room, hotel: hotel, room_type: room_type, number: "102")
      archived_room = create(:room, hotel: hotel, room_type: room_type, room_group: room_group, number: "103", archived_at: 1.day.ago)

      patch hotel_room_group_path(hotel, room_group),
            params: { room_group: { name: "Renamed Tower", room_ids: [ added_room.id ] } },
            as: :turbo_stream

      expect(room_group.reload.name).to eq("Renamed Tower")
      expect(added_room.reload.room_group).to eq(room_group)
      expect(removed_room.reload.room_group).to be_nil
      expect(archived_room.reload.room_group).to eq(room_group)
      expect(response.body).to include('action="complete_sheet"')
    end

    it "permits an empty active-room selection" do
      room = create(:room, hotel: hotel, room_type: create(:room_type, hotel: hotel), room_group: room_group)

      patch hotel_room_group_path(hotel, room_group),
            params: { room_group: { name: room_group.name, room_ids: [ "" ] } }

      expect(response).to redirect_to(hotel_room_groups_path(hotel))
      expect(room.reload.room_group).to be_nil
    end

    it "rejects a room from another property" do
      foreign_room = create(:room)

      patch hotel_room_group_path(hotel, room_group),
            params: { room_group: { name: "Changed", room_ids: [ foreign_room.id ] } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.text.squish).to include("Rooms include one or more rooms that are not available for this property")
      expect(room_group.reload.name).to eq("Main Tower")
    end
  end

  describe "DELETE #destroy" do
    it "deletes the group and leaves active and archived rooms unassigned" do
      room_type = create(:room_type, hotel: hotel)
      active_room = create(:room, hotel: hotel, room_type: room_type, room_group: room_group)
      archived_room = create(:room, hotel: hotel, room_type: room_type, room_group: room_group, archived_at: 1.day.ago)

      expect {
        delete hotel_room_group_path(hotel, room_group)
      }.to change(RoomGroup, :count).by(-1)

      expect(active_room.reload.room_group).to be_nil
      expect(archived_room.reload.room_group).to be_nil
      expect(response).to redirect_to(hotel_room_groups_path(hotel))
    end
  end

  it "permanently redirects the former room-groups URL" do
    get hotel_legacy_room_groups_path(hotel)

    expect(response).to redirect_to(hotel_room_groups_path(hotel))
    expect(response).to have_http_status(:moved_permanently)
  end
end
