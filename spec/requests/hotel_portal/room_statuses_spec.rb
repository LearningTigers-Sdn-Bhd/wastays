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
    create(:room_status, hotel: hotel, room_type: room_type, room_number: room_number, status: "dirty")
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
        room_status: { status: "cleaning", notes: "Started cleaning" },
        start_date: Date.new(2026, 5, 7).to_s,
        days: 21,
        layout: "compact"
      }

      expect(response).to redirect_to(hotel_room_status_board_path(hotel, start_date: "2026-05-07", days: "21", layout: "compact"))
      expect(room_status.reload.status).to eq("cleaning")
    end

    it "saves inspection failed notes" do
      grant_manage_room_status
      room_status = room_status_for
      room_status.update!(status: "awaiting_inspection")

      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { status: "inspection_failed", notes: "Need to reclean the bathroom." },
        start_date: Date.new(2026, 5, 7).to_s,
        days: 21,
        layout: "compact"
      }

      expect(response).to redirect_to(hotel_room_status_board_path(hotel, start_date: "2026-05-07", days: "21", layout: "compact"))
      expect(room_status.reload.status).to eq("inspection_failed")
      expect(room_status.reload.notes).to eq("Need to reclean the bathroom.")
    end

    it "detects late checkout and moves the active booking to review due out" do
      grant_manage_room_status
      room_status = room_status_for
      booking = create(:booking, hotel: hotel, status: "checked_in")
      create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { status: "late_checkout_detected", notes: "Guest still in room" },
        start_date: Date.new(2026, 5, 7).to_s,
        days: 21,
        layout: "compact"
      }

      expect(response).to redirect_to(hotel_room_status_board_path(hotel, start_date: "2026-05-07", days: "21", layout: "compact"))
      expect(room_status.reload.status).to eq("late_checkout_detected")
      expect(booking.reload.status).to eq("review_due_out")
    end

    it "blocks users without manage_room_status permission" do
      room_status = room_status_for

      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { status: "ready" }
      }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("not authorized")
      expect(room_status.reload.status).to eq("dirty")
    end

    it "blocks account-level manage_room_status permission without hotel-scoped access" do
      account_role = create(:role, account: user.account)
      create(:role_permission, role: account_role, permission: manage_room_status_permission)
      create(:user_role, user: user, role: account_role)
      room_status = room_status_for

      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { status: "cleaning" }
      }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include("not authorized")
      expect(room_status.reload.status).to eq("dirty")
    end

    it "allows toggling the priority flag" do
      grant_manage_room_status
      room_status = room_status_for
      expect(room_status.priority).to be false

      # Mark priority
      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { priority: "true" }
      }
      expect(response).to redirect_to(hotel_room_status_board_path(hotel))
      expect(room_status.reload.priority).to be true

      # Remove priority
      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { priority: "false" }
      }
      expect(response).to redirect_to(hotel_room_status_board_path(hotel))
      expect(room_status.reload.priority).to be false
    end

    it "retains the priority flag when marked as ready" do
      grant_manage_room_status
      room_status = room_status_for
      room_status.update!(priority: true)
      expect(room_status.priority).to be true

      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { status: "ready", notes: "Cleaned and ready." }
      }
      expect(response).to redirect_to(hotel_room_status_board_path(hotel))
      expect(room_status.reload.status).to eq("ready")
      expect(room_status.priority).to be true
    end

    it "allows toggling the priority flag and adding optional notes" do
      grant_manage_room_status
      room_status = room_status_for
      expect(room_status.priority).to be false

      # Mark priority with notes
      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { priority: "true", notes: "Need early prep for VIP." }
      }
      expect(response).to redirect_to(hotel_room_status_board_path(hotel))
      expect(room_status.reload.priority).to be true
      expect(room_status.priority_note).to eq("Need early prep for VIP.")
      expect(room_status.notes).to be_nil
    end

    it "allows toggling the DND flag and sets the dnd_date" do
      grant_manage_room_status
      room_status = room_status_for
      expect(room_status.dnd).to be false
      expect(room_status.dnd_date).to be_nil

      # Enable DND
      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { dnd: "true" }
      }
      expect(response).to redirect_to(hotel_room_status_board_path(hotel))
      expect(room_status.reload.dnd).to be true
      expect(room_status.dnd_date).to eq(hotel.current_business_date)

      # Disable DND
      patch hotel_room_status_path(hotel, room_status), params: {
        room_status: { dnd: "false" }
      }
      expect(response).to redirect_to(hotel_room_status_board_path(hotel))
      expect(room_status.reload.dnd).to be false
      expect(room_status.dnd_date).to be_nil
    end
  end
end
