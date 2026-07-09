# frozen_string_literal: true

require "rails_helper"

RSpec.describe "HotelPortal::Bookings::Transactions::UndoCheckIns", type: :request do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 3, room_number_mode: "custom", room_numbers: [ "101", "102", "103" ]) }
  let(:user) { create(:user, :superadmin) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", checked_in_at: Date.current - 1.day) }

  before do
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    sign_in_as(user)
  end

  def create_group_child(group, status:, room_number:)
    attributes = { hotel: hotel, group_booking: group, status: status, guest_name: "Group Member" }
    booking = create(:booking, attributes)
    create(:booking_room, booking: booking, room_type: room_type, room_number: room_number, subtotal: 200.0)
    create(:booking_guest, booking: booking, guest: create(:guest, name: "Group Member"), is_primary: true)
    booking
  end

  describe "GET /show" do
    it "renders the undo check-in offcanvas drawer" do
      get hotel_booking_transaction_undo_check_in_path(hotel, booking), headers: { "Turbo-Frame" => "offcanvas_drawer" }

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Undo Check-In")
      expect(response.body).to include("Reason to change")
    end
  end

  describe "POST /submit" do
    context "single booking" do
      it "fails to undo check-in if retroactive_reason is blank" do
        post hotel_booking_transaction_undo_check_in_path(hotel, booking), params: {
          retroactive_reason: ""
        }

        expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "booking_details"))
        expect(flash[:alert]).to include("Reason to change is required")
        expect(booking.reload.status).to eq("checked_in")
      end

      it "successfully undoes check-in when reason is provided" do
        expect {
          post hotel_booking_transaction_undo_check_in_path(hotel, booking), params: {
            retroactive_reason: "Mistaken check-in"
          }
        }.to change(BookingAuditLog, :count).by(1)

        expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "booking_details"))
        expect(flash[:notice]).to include("Check-in undone successfully")

        booking.reload
        expect(booking.status).to eq("confirmed")
        expect(booking.checked_in_at).to be_nil

        audit_log = BookingAuditLog.last
        expect(audit_log.action_type).to eq("undo_check_in")
        expect(audit_log.metadata["reason"]).to eq("Mistaken check-in")
      end
    end

    context "group booking" do
      let(:group) { create(:group_booking, hotel: hotel) }
      let!(:first) { create_group_child(group, status: "checked_in", room_number: "101") }
      let!(:second) { create_group_child(group, status: "checked_in", room_number: "102") }

      before do
        first.update_columns(checked_in_at: Date.current - 1.day)
        second.update_columns(checked_in_at: Date.current - 1.day)
      end

      it "undoes check-in in bulk for all selected group bookings" do
        post hotel_booking_transaction_undo_check_in_path(hotel, first), params: {
          target_scope: "group",
          booking_ids: [ first.id, second.id ],
          retroactive_reason: "Group check-in error"
        }

        expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, first, tab: "booking_details"))
        expect(flash[:notice]).to include("2 bookings check-in undone")

        expect(first.reload.status).to eq("confirmed")
        expect(second.reload.status).to eq("confirmed")
        expect(first.checked_in_at).to be_nil
        expect(second.checked_in_at).to be_nil
      end
    end
  end
end
