# frozen_string_literal: true

require "rails_helper"

RSpec.describe RoomOperationalAuditLog, type: :model do
  it "requires an event type, room number, and metadata" do
    log = build(:room_operational_audit_log, event_type: nil, room_number: nil, metadata: nil)

    expect(log).not_to be_valid
    expect(log.errors[:event_type]).to include("can't be blank")
    expect(log.errors[:room_number]).to include("can't be blank")
    expect(log.errors[:metadata]).to include("can't be blank")
  end

  it "accepts status change events" do
    log = build(:room_operational_audit_log, event_type: "room_status_changed")

    expect(log).to be_valid
  end

  it "rejects unknown event types" do
    log = build(:room_operational_audit_log, event_type: "unknown")

    expect(log).not_to be_valid
    expect(log.errors[:event_type]).to include("is not included in the list")
  end
end
