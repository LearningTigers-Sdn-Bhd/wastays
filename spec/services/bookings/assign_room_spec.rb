# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::AssignRoom do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101", "102" ], quantity: 2) }
  let(:booking) { create(:booking, hotel: hotel, status: "confirmed") }
  let(:user) { create(:user) }

  before do
    create(:booking_room, booking: booking, room_type: room_type, room_number: nil, quantity: 1, subtotal: 200)
  end

  it "assigns a ready room" do
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")

    expect {
      result = described_class.new(booking: booking, room_number: "101", user: user).call
      expect(result).to be_success
    }.to change(BookingAuditLog, :count).by(1)

    expect(booking.booking_rooms.first.reload.room_number).to eq("101")

    log = BookingAuditLog.last
    expect(log.action_type).to eq("room_assignment")
    expect(log.auditable).to eq(booking.booking_rooms.first)
  end

  it "blocks dirty rooms for normal users" do
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")

    result = described_class.new(booking: booking, room_number: "101", user: user).call

    expect(result).not_to be_success
    expect(result.error).to eq("Room 101 is Dirty and cannot be assigned until it is ready.")
    expect(booking.booking_rooms.first.reload.room_number).to be_nil
  end

  it "allows manager override with permission and reason" do
    permission = create(:permission, slug: "override_room_status_assignment", name: "Override Room Status Assignment")
    role = create(:role, account: hotel.account)
    create(:role_permission, role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")

    result = described_class.new(
      booking: booking,
      room_number: "101",
      user: user,
      override: true,
      override_reason: "Housekeeping verbally confirmed ready"
    ).call

    expect(result).to be_success
    expect(booking.booking_rooms.first.reload.room_number).to eq("101")

    log = RoomOperationalAuditLog.find_by!(event_type: "assignment_override")
    expect(log.reason).to eq("Housekeeping verbally confirmed ready")
  end

  it "allows room-number-only assignment while night audit is running" do
    hotel.current_business_date_record.update!(status: "audit_running")
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")

    result = described_class.new(booking: booking, room_number: "101", user: user).call

    expect(result).to be_success
    expect(booking.booking_rooms.first.reload.room_number).to eq("101")
  end
end
