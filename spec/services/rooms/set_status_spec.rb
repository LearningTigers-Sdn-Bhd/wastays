# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::SetStatus do
  let(:hotel) { create(:hotel) }
  let(:user) { create(:user) }
  let(:room_type) { create(:room_type, hotel: hotel, quantity: 1, room_numbers: [ "101" ]) }

  it "updates a room status and writes an audit log" do
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")

    result = described_class.new(
      room_status: room_status,
      status: "cleaning",
      user: user,
      reason: "Housekeeping started"
    ).call

    expect(result).to be_success
    expect(room_status.reload.status).to eq("cleaning")
    expect(room_status.last_changed_by).to eq(user)
    expect(room_status.last_changed_at).to be_present

    log = RoomOperationalAuditLog.last
    expect(log.event_type).to eq("room_status_changed")
    expect(log.old_status).to eq("dirty")
    expect(log.new_status).to eq("cleaning")
    expect(log.reason).to eq("Housekeeping started")
  end

  it "allows ready status to change to dirty" do
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "ready")

    result = described_class.new(
      room_status: room_status,
      status: "dirty",
      user: user,
      reason: "Room became dirty"
    ).call

    expect(result).to be_success
    expect(room_status.reload.status).to eq("dirty")
  end

  it "rejects unsupported transitions" do
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")

    result = described_class.new(room_status: room_status, status: "inspection_failed", user: user).call

    expect(result).not_to be_success
    expect(result.error).to eq("Cannot change room 101 from dirty to inspection_failed.")
    expect(room_status.reload.status).to eq("dirty")
  end

  it "transitions associated booking to due_out_detected when status is late_checkout_detected" do
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "dirty")
    booking = create(:booking, hotel: hotel, status: "checked_in")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    result = described_class.new(
      room_status: room_status,
      status: "late_checkout_detected",
      user: user,
      reason: "Guest still in room",
      booking: booking
    ).call

    expect(result).to be_success
    expect(booking.reload.status).to eq("due_out_detected")

    log = BookingAuditLog.last
    expect(log.auditable).to eq(booking)
    expect(log.action_type).to eq("status_change")
    expect(log.metadata["to"]).to eq("due_out_detected")
    expect(log.metadata["event"]).to eq("detect_due_out")
  end

  it "allows marking a room as ready without a note" do
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "cleaning")

    result = described_class.new(
      room_status: room_status,
      status: "ready",
      user: user,
      reason: ""
    ).call

    expect(result).to be_success
    expect(room_status.reload.status).to eq("ready")
  end

  it "allows marking a room as ready with a note" do
    room_status = create(:room_status, hotel: hotel, room_type: room_type, room_number: "101", status: "cleaning")

    result = described_class.new(
      room_status: room_status,
      status: "ready",
      user: user,
      reason: "Room is clean and inspected"
    ).call

    expect(result).to be_success
    expect(room_status.reload.status).to eq("ready")
    expect(room_status.reload.notes).to eq("Room is clean and inspected")
  end
end
