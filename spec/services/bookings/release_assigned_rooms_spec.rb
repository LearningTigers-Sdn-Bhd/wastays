# frozen_string_literal: true

require "rails_helper"

RSpec.describe Bookings::ReleaseAssignedRooms do
  it "marks assigned rooms ready and records the operational release" do
    hotel = create(:hotel)
    user = create(:user, account: hotel.account)
    room_type = create(:room_type, hotel: hotel, quantity: 1, room_numbers: [ "101" ])
    booking = create(:booking, hotel: hotel)
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")

    result = described_class.call(
      booking: booking,
      user: user,
      event_type: "no_show_released",
      reason: "No-show finalized"
    )

    expect(result.success?).to be(true)
    expect(room_status.reload.status).to eq("ready")
    expect(RoomOperationalAuditLog.where(booking: booking, event_type: "no_show_released")).to exist
  end
end
