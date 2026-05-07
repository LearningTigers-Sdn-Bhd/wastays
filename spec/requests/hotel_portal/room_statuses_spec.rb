# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::RoomStatuses", type: :request do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101" ], quantity: 1) }
  let(:manage_room_status_permission) do
    Permission.find_by(slug: "manage_room_status") || create(:permission, slug: "manage_room_status", name: "Manage Room Status")
  end
  let(:role) { create(:role, account: hotel.account, slug: "front_desk", name: "Front Desk") }

  def room_status_for(room_number: "101")
    create(:room_status, hotel: hotel, room_type: room_type, room_number: room_number, status: "pending_cleaning")
  end

  def grant_manage_room_status
    create(:role_permission, role: role, permission: manage_room_status_permission)
  end

  before do
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  describe "PATCH /hotel/:hotel_id/room_statuses/:id" do
    it "updates a room status" do
      grant_manage_room_status
      room_status = room_status_for

      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { status: "preparing", notes: "Started cleaning" }
      }

      expect(response).to redirect_to(hotel_room_status_board_path(hotel))
      expect(room_status.reload.status).to eq("preparing")
    end

    it "blocks users without manage_room_status permission" do
      room_status = room_status_for

      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { status: "ready" }
      }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("not authorized")
      expect(room_status.reload.status).to eq("pending_cleaning")
    end

    it "blocks account-level manage_room_status permission without hotel-scoped access" do
      account_role = create(:role, account: user.account)
      create(:role_permission, role: account_role, permission: manage_room_status_permission)
      create(:user_role, user: user, role: account_role)
      room_status = room_status_for

      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { status: "preparing" }
      }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("not authorized")
      expect(room_status.reload.status).to eq("pending_cleaning")
    end
  end
end
