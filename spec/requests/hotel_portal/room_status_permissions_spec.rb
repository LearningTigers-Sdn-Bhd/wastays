# frozen_string_literal: true

require "rails_helper"
load Rails.root.join("db/migrate/20260506000002_add_room_readiness_permissions.rb")

RSpec.describe "Room status permissions", type: :request do
  def room_status_for(hotel:, room_number: "101")
    room_type = create(:room_type, hotel: hotel, room_numbers: [ room_number ], quantity: 1)
    create(:room_status, hotel: hotel, room_type: room_type, room_number: room_number, status: "pending_cleaning")
  end

  it "blocks room status updates without manage_room_status permission" do
    hotel = create(:hotel)
    user = create(:user)
    create(:user_hotel_access, user: user, hotel: hotel)
    room_status = room_status_for(hotel: hotel)
    sign_in_as(user)

    patch hotel_room_status_path(hotel, room_status), params: {
      room_status: { status: "preparing", notes: "Started cleaning" }
    }

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("not authorized")
    expect(room_status.reload.status).to eq("pending_cleaning")
  end

  it "allows room status updates when role has manage_room_status permission" do
    hotel = create(:hotel)
    user = create(:user)
    AddRoomReadinessPermissions.new.up unless Permission.exists?(slug: "manage_room_status")
    role = create(:role, account: hotel.account, slug: "front_desk", name: "Front Desk")
    permission = Permission.find_by!(slug: "manage_room_status")
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    room_status = room_status_for(hotel: hotel, room_number: "102")
    sign_in_as(user)

    patch hotel_room_status_path(hotel, room_status), params: {
      room_status: { status: "preparing", notes: "Started cleaning" }
    }

    expect(response).to redirect_to(hotel_room_status_board_path(hotel))
    expect(room_status.reload.status).to eq("preparing")
  end
end
