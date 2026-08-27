# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::RemovalGuard do
  let(:hotel) { create(:hotel, accounting_business_date: Date.current) }
  let(:room_type) { create(:room_type, sync_rooms: false, hotel: hotel, quantity: 1, room_numbers: [ "101" ]) }
  let(:room) { create(:room, hotel: hotel, room_type: room_type, number: "101") }

  it "blocks a room with a nonterminal assigned booking" do
    booking = create(:booking, hotel: hotel, status: "confirmed")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    result = described_class.call(room: room)

    expect(result).not_to be_success
    expect(result.reasons).to include(:assigned_booking)
  end

  it "does not block a room with only terminal bookings" do
    booking = create(:booking, hotel: hotel, status: "completed")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")

    expect(described_class.call(room: room)).to be_success
  end

  it "blocks an incomplete current or future room block" do
    create(
      :room_block,
      hotel: hotel,
      room_type: room_type,
      room_number: "101",
      start_date: Date.current + 2.days,
      end_date: Date.current + 3.days
    )

    result = described_class.call(room: room)

    expect(result).not_to be_success
    expect(result.reasons).to include(:room_block)
  end

  it "does not block a completed room block" do
    create(
      :room_block,
      hotel: hotel,
      room_type: room_type,
      room_number: "101",
      completed_at: Time.current
    )

    expect(described_class.call(room: room)).to be_success
  end

  it "does not block an incomplete room block that ended before the business date" do
    create(
      :room_block,
      hotel: hotel,
      room_type: room_type,
      room_number: "101",
      start_date: Date.current - 2.days,
      end_date: Date.current - 1.day
    )

    expect(described_class.call(room: room)).to be_success
  end

  it "blocks an active room lock but not an expired lock" do
    active_lock = create(:room_lock, hotel: hotel, room_type: room_type, room_number: "101", expires_at: 10.minutes.from_now)

    expect(described_class.call(room: room).reasons).to include(:room_lock)

    active_lock.update!(expires_at: 1.minute.ago)
    expect(described_class.call(room: room)).to be_success
  end

  it "blocks a direct open housekeeping task" do
    create(
      :housekeeping_request,
      booking: nil,
      hotel: hotel,
      room_type: room_type,
      room_number: "101",
      status: "assigned",
      work_context: "vacant_room_task"
    )

    result = described_class.call(room: room)

    expect(result).not_to be_success
    expect(result.reasons).to include(:housekeeping_task)
  end

  it "resolves an open housekeeping task through its booking room" do
    booking = create(:booking, hotel: hotel, status: "completed")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    create(
      :housekeeping_request,
      booking: booking,
      hotel: nil,
      room_type: nil,
      room_number: nil,
      status: "in_progress",
      work_context: "checkout_turnover"
    )

    result = described_class.call(room: room)

    expect(result).not_to be_success
    expect(result.reasons).to include(:housekeeping_task)
  end

  it "does not block closed housekeeping or historical operational records" do
    create(
      :housekeeping_request,
      booking: nil,
      hotel: hotel,
      room_type: room_type,
      room_number: "101",
      status: "completed",
      work_context: "vacant_room_task"
    )
    create(:room_status, hotel: hotel, room_type: room_type, room_number: "101")
    create(:room_operational_audit_log, hotel: hotel, room_type: room_type, room_number: "101")

    expect(described_class.call(room: room)).to be_success
  end
end
