# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::RoomStatuses", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101" ], quantity: 1) }

  before do
    permission = create(:permission, slug: "manage_room_status", name: "Manage Room Status")
    role = create(:role, account: hotel.account)
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "updates a room status" do
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "pending_cleaning")

    patch hotel_room_status_path(hotel, room_status), params: {
      room_status: { status: "preparing", notes: "Started cleaning" }
    }

    expect(response).to redirect_to(hotel_room_status_board_path(hotel))
    expect(room_status.reload.status).to eq("preparing")
  end

  it "blocks users without manage_room_status permission" do
    role = user.user_hotel_accesses.find_by!(hotel: hotel).role
    role.permissions.delete(Permission.find_by!(slug: "manage_room_status"))

    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "pending_cleaning")

    patch hotel_room_status_path(hotel, room_status), params: {
      room_status: { status: "ready" }
    }

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("not authorized")
    expect(room_status.reload.status).to eq("pending_cleaning")
  end
end
