# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::SetStatus do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel, room_numbers: [ "101" ]) }

  it "updates a room status and writes an audit log" do
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "pending_cleaning")

    result = described_class.new(
      room_status: room_status,
      status: "preparing",
      user: user,
      reason: "Housekeeping started"
    ).call

    expect(result).to be_success
    expect(room_status.reload.status).to eq("preparing")
    expect(room_status.last_changed_by).to eq(user)
    expect(room_status.last_changed_at).to be_present

    log = RoomOperationalAuditLog.last
    expect(log.event_type).to eq("room_status_changed")
    expect(log.old_status).to eq("pending_cleaning")
    expect(log.new_status).to eq("preparing")
    expect(log.reason).to eq("Housekeeping started")
  end

  it "rejects unsupported transitions" do
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "pending_cleaning")

    result = described_class.new(room_status: room_status, status: "inspection_failed", user: user).call

    expect(result).not_to be_success
    expect(result.error).to eq("Cannot change room 101 from pending_cleaning to inspection_failed.")
    expect(room_status.reload.status).to eq("pending_cleaning")
  end

  it "transitions associated booking to review_due_out when status is late_checkout_detected" do
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "pending_cleaning")
    booking = create(:booking, hotel: hotel, status: "checked_in")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    result = described_class.new(
      room_status: room_status,
      status: "late_checkout_detected",
      user: user,
      reason: "Guest still in room"
    ).call

    expect(result).to be_success
    expect(booking.reload.status).to eq("review_due_out")
    
    log = BookingAuditLog.last
    expect(log.auditable).to eq(booking)
    expect(log.action_type).to eq("status_change")
    expect(log.metadata["to"]).to eq("review_due_out")
    expect(log.metadata["event"]).to eq("detect_late_checkout")
  end
end
