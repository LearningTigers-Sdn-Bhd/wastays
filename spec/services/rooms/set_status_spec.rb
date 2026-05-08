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
end
