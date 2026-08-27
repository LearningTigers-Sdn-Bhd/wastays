# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::Rename do
  let(:hotel) { create(:hotel) }
  let!(:room_type) do
    create(:room_type, hotel:, room_number_mode: "custom", quantity: 2, room_numbers: %w[101 102])
  end
  let(:room) { hotel.rooms.find_by!(number: "101") }

  it "keeps the room's identity and moves its number" do
    result = described_class.call(room:, number: "1A")

    expect(result).to be_success
    expect(room.reload.number).to eq("1A")
    expect(room.id).to eq(result.room.id)
  end

  it "carries the room status, block, and lock to the new number" do
    status = create(:room_status, hotel:, room_type:, room_number: "101")
    block = create(:room_block, hotel:, room_type:, room_number: "101")
    lock = create(:room_lock, hotel:, room_type:, user: create(:user), room_number: "101", expires_at: 1.hour.from_now)

    described_class.call(room:, number: "1A")

    expect(status.reload.room_number).to eq("1A")
    expect(block.reload.room_number).to eq("1A")
    expect(lock.reload.room_number).to eq("1A")
    expect([ status, block, lock ].map(&:room_id)).to all(eq(room.id))
  end

  it "leaves a booking and an audit log at the number they were written with" do
    booking = create(:booking, hotel:)
    booking_room = create(:booking_room, booking:, room_type:, room_number: "101")
    log = create(:room_operational_audit_log, hotel:, room_type:, room_number: "101")

    described_class.call(room:, number: "1A")

    expect(booking_room.reload.room_number).to eq("101")
    expect(log.reload.room_number).to eq("101")
    expect(booking_room.room_id).to eq(room.id)
    expect(log.room_id).to eq(room.id)
  end

  it "shows the new number on the boards" do
    described_class.call(room:, number: "1A")

    expect(Rooms::DirectoryQuery.for_room_type(room_type).numbers).to contain_exactly("1A", "102")
  end

  it "refuses a number another room already holds" do
    result = described_class.call(room:, number: "102")

    expect(result).not_to be_success
    expect(result.error).to eq("Room 102 already belongs to this property.")
    expect(room.reload.number).to eq("101")
  end

  it "refuses a blank number" do
    result = described_class.call(room:, number: "  ")

    expect(result).not_to be_success
    expect(room.reload.number).to eq("101")
  end

  it "refuses to rename an archived room" do
    renumber_room_type!(room_type, %w[102])

    result = described_class.call(room: room.reload, number: "1A")

    expect(result).not_to be_success
    expect(result.error).to eq("Restore the room before you rename it.")
  end

  it "does nothing when the number does not change" do
    status = create(:room_status, hotel:, room_type:, room_number: "101")

    expect(described_class.call(room:, number: "101")).to be_success
    expect(status.reload.room_number).to eq("101")
  end

  it "trims the number before it saves" do
    described_class.call(room:, number: "  1A  ")

    expect(room.reload.number).to eq("1A")
  end

  it "leaves every record alone when the rename fails" do
    status = create(:room_status, hotel:, room_type:, room_number: "101")

    described_class.call(room:, number: "102")

    expect(status.reload.room_number).to eq("101")
    expect(room.reload.number).to eq("101")
  end
end
