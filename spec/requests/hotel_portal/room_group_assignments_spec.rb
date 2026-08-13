# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::RoomGroupAssignments", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account) }
  let(:user) { create(:user, account: account) }
  let!(:group) { create(:room_group, hotel: hotel, name: "Main Tower") }
  let!(:room_type) { create(:room_type, hotel: hotel, room_group: nil, name: "Deluxe Room") }

  before do
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(HotelPortal::BaseController).to receive(:current_hotel).and_return(hotel)
    allow_any_instance_of(HotelPortal::RoomGroupAssignmentsController).to receive(:authorize).and_return(true)
  end

  it "renders the group selector and preselected room-category multiselect" do
    get new_hotel_room_group_assignment_path(hotel, room_type_id: room_type.id)

    expect(response).to have_http_status(:ok)
    document = response.parsed_body
    sheet = document.at_css("#assign-room-group-sheet")
    expect(sheet).to be_present
    group_options = sheet.css("select[name='room_group_assignment[room_group_id]'] option")
    expect(group_options.map { |option| option["value"] }).to include("new", group.id.to_s)
    selected_rooms = sheet.css("select[name='room_group_assignment[room_type_ids][]'] option[selected]")
    expect(selected_rooms.map { |option| option["value"] }).to eq([ room_type.id.to_s ])
  end

  it "moves selected categories while preserving unrelated target members" do
    existing_member = create(:room_type, hotel: hotel, room_group: group)
    other_group = create(:room_group, hotel: hotel)
    moving_room = create(:room_type, hotel: hotel, room_group: other_group)

    post hotel_room_group_assignment_path(hotel), params: {
      room_group_assignment: { room_group_id: group.id, room_type_ids: [ room_type.id, moving_room.id ] }
    }, as: :turbo_stream

    expect(response).to have_http_status(:ok)
    expect(room_type.reload.room_group).to eq(group)
    expect(moving_room.reload.room_group).to eq(group)
    expect(existing_member.reload.room_group).to eq(group)
  end

  it "creates a new group from the selector and assigns the selected categories" do
    expect {
      post hotel_room_group_assignment_path(hotel), params: {
        room_group_assignment: {
          room_group_id: "new",
          new_group_name: "Garden Wing",
          room_type_ids: [ room_type.id ]
        }
      }, as: :turbo_stream
    }.to change(RoomGroup, :count).by(1)

    expect(room_type.reload.room_group.name).to eq("Garden Wing")
  end

  it "rolls back assignment when a new group is invalid" do
    create(:room_group, hotel: hotel, name: "Garden Wing")

    expect {
      post hotel_room_group_assignment_path(hotel), params: {
        room_group_assignment: {
          room_group_id: "new",
          new_group_name: "Garden Wing",
          room_type_ids: [ room_type.id ]
        }
      }
    }.not_to change(RoomGroup, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(room_type.reload.room_group).to be_nil
  end

  it "rejects empty and cross-property selections" do
    other_room = create(:room_type)

    post hotel_room_group_assignment_path(hotel), params: {
      room_group_assignment: { room_group_id: group.id, room_type_ids: [ other_room.id ] }
    }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body.at_css("[role='alert'], .panel-form-field[data-invalid='true']")).to be_present
    expect(room_type.reload.room_group).to be_nil
  end
end
