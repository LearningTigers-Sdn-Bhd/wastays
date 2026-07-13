require "rails_helper"

RSpec.describe "HotelPortal::Bookings::CheckIns", type: :request do
  let(:hotel) { create(:hotel, tourism_tax_enabled: true, tourism_tax_amount: 10.0) }
  let(:user) { create(:user, :superadmin) }
  let(:room_type) { create(:room_type, hotel: hotel) }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      guest_country: "United States",
      tourism_tax_applied: true,
      tourism_tax_amount: 20.0,
      tax_posting_snapshot: {
        Date.current.iso8601 => [ { "name" => "Tourism Tax", "type" => "tourism_tax", "amount" => "20.00" } ]
      },
      booking_quote: nil
    )
  end

  before do
    create(:booking_room, booking: booking, room_type: room_type)
    sign_in_as(user)
  end

  describe "POST /create" do
    it "posts a cash folio payment when tourism tax is collected and ignores submitted amount" do
      expect {
        post check_in_hotel_booking_path(hotel, booking, format: :html), params: {
          override_night_audit: "1",
          retroactive_reason: "Test reason",
          booking: {
            tourism_tax_collected: "1",
            tourism_tax_amount: "50.00",
            booking_rooms_attributes: [
              { id: booking.booking_rooms.first.id, room_number: "101" }
            ]
          }
        }
      }.to change(FolioTransaction.payment, :count).by(1)

      payment = booking.reload.booking_folio.folio_transactions.payment.sole
      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "booking_details"))
      expect(booking.status).to eq("checked_in")
      expect(booking.tourism_tax_collected).to be true
      expect(booking.tourism_tax_amount).to eq(20.00) # Remains unchanged
      expect(payment.category).to eq("cash")
      expect(payment.amount).to eq(20.to_d)
      expect(payment.metadata["source"]).to eq("tourism_tax_check_in")
    end

    it "does not duplicate tourism tax folio payment on repeated check-in save" do
      post check_in_hotel_booking_path(hotel, booking, format: :html), params: {
        override_night_audit: "1",
        retroactive_reason: "Test reason",
        booking: {
          tourism_tax_collected: "1",
          booking_rooms_attributes: [
            { id: booking.booking_rooms.first.id, room_number: "101" }
          ]
        }
      }

      expect {
        post check_in_hotel_booking_path(hotel, booking, format: :html), params: {
          override_night_audit: "1",
          retroactive_reason: "Test reason",
          booking: {
            tourism_tax_collected: "1",
            booking_rooms_attributes: [
              { id: booking.booking_rooms.first.id, room_number: "101" }
            ]
          }
        }
      }.not_to change(FolioTransaction.payment, :count)

      expect(booking.reload.tourism_tax_collected).to be true
    end

    it "can set tourism_tax_collected to false without posting a payment" do
      booking.update!(tourism_tax_collected: true)

      expect {
        post check_in_hotel_booking_path(hotel, booking, format: :html), params: {
          override_night_audit: "1",
          retroactive_reason: "Test reason",
          booking: {
            tourism_tax_collected: "0",
            booking_rooms_attributes: [
              { id: booking.booking_rooms.first.id, room_number: "101" }
            ]
          }
        }
      }.not_to change(FolioTransaction.payment, :count)

      expect(booking.reload.tourism_tax_collected).to be false
    end

    it "requires a Reason to change when saving edits to an already checked-in booking" do
      booking.update_columns(status: "checked_in")

      post check_in_hotel_booking_path(hotel, booking, format: :html), params: {
        booking: {
          booking_rooms_attributes: [
            { id: booking.booking_rooms.first.id, room_number: "101" }
          ]
        }
      }

      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "booking_details"))
      expect(flash[:alert]).to include("Reason to change is required")
    end

    it "succeeds and records an audit log when Reason to change is provided" do
      booking.update_columns(status: "checked_in", checked_in_at: Date.current - 1.day)
      original_check_in = booking.checked_in_at

      expect {
        post check_in_hotel_booking_path(hotel, booking, format: :html), params: {
          retroactive_reason: "Correcting check-in time",
          booking: {
            checked_in_at: (Date.current - 2.days).to_s,
            booking_rooms_attributes: [
              { id: booking.booking_rooms.first.id, room_number: "101" }
            ]
          }
        }
      }.to change(BookingAuditLog, :count).by(1)

      expect(response).to redirect_to(hotel_booking_control_panel_path(hotel, booking, tab: "booking_details"))
      expect(booking.reload.checked_in_at).not_to eq(original_check_in)
      expect(BookingAuditLog.last.action_type).to eq("edit_check_in")
      expect(BookingAuditLog.last.metadata["reason"]).to eq("Correcting check-in time")
    end
  end
end
