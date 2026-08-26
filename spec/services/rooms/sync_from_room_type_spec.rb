# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::SyncFromRoomType do
  let(:hotel) { create(:hotel) }
  let(:room_group) { create(:room_group, hotel: hotel) }
  let(:room_type) do
    create(
      :room_type,
      hotel: hotel,
      room_group: room_group,
      quantity: 2,
      room_numbers: %w[101 102]
    )
  end

  def create_room(number:, position:, room_group: nil, archived_at: nil)
    create(
      :room,
      hotel: hotel,
      room_type: room_type,
      room_group: room_group,
      number: number,
      position: position,
      archived_at: archived_at
    )
  end

  it "preserves unchanged identities and group assignments" do
    first = create_room(number: "101", position: 1, room_group: room_group)
    second = create_room(number: "102", position: 0)

    result = described_class.call(room_type: room_type)

    expect(result).to be_success
    expect(result.rooms.map(&:id)).to eq([ first.id, second.id ])
    expect(first.reload).to have_attributes(position: 0, room_group_id: room_group.id, archived_at: nil)
    expect(second.reload).to have_attributes(position: 1, room_group_id: nil, archived_at: nil)
  end

  it "creates new rooms with the legacy room group" do
    result = described_class.call(room_type: room_type)

    expect(result).to be_success
    expect(result.rooms.map(&:number)).to eq(%w[101 102])
    expect(result.rooms.map(&:position)).to eq([ 0, 1 ])
    expect(result.rooms.map(&:room_group_id)).to eq([ room_group.id, room_group.id ])
  end

  it "restores the archived identity without changing its group" do
    old_group = create(:room_group, hotel: hotel)
    archived = create_room(number: "101", position: 8, room_group: old_group, archived_at: 1.day.ago)

    result = described_class.call(room_type: room_type)

    expect(result).to be_success
    expect(result.rooms.first.id).to eq(archived.id)
    expect(archived.reload).to have_attributes(position: 0, room_group_id: old_group.id, archived_at: nil)
  end

  it "archives removed rooms and does not infer a rename" do
    old_room = create_room(number: "101", position: 0, room_group: room_group)
    room_type.update!(room_numbers: %w[201 102])

    result = described_class.call(room_type: room_type)

    expect(result).to be_success
    expect(old_room.reload.archived_at).to be_present
    expect(result.rooms.map(&:number)).to eq(%w[201 102])
    expect(result.rooms.first.id).not_to eq(old_room.id)
    expect(result.rooms.first.room_group_id).to eq(room_group.id)
  end

  it "rejects a number that belongs to another room category" do
    other_type = create(:room_type, hotel: hotel, quantity: 1, room_numbers: [ "101" ])
    other_room = create(:room, hotel: hotel, room_type: other_type, number: "101")

    result = described_class.call(room_type: room_type)

    expect(result).not_to be_success
    expect(result.error).to eq("Room 101 already belongs to another room category.")
    expect(other_room.reload.archived_at).to be_nil
    expect(Room.where(room_type: room_type)).to be_empty
  end

  it "rejects room numbers that duplicate after normalization" do
    room_type.update_column(:room_numbers, [ "101", " 101 " ])

    result = described_class.call(room_type: room_type)

    expect(result).not_to be_success
    expect(result.error).to eq("Room numbers must be unique.")
    expect(Room.where(room_type: room_type)).to be_empty
  end

  it "returns a failure without changing rooms when a removal is blocked" do
    protected_room = create_room(number: "101", position: 0)
    kept_room = create_room(number: "102", position: 1)
    booking = create(:booking, hotel: hotel, status: "confirmed")
    create(:booking_room, booking: booking, room_type: room_type, room_number: "101")
    room_type.update!(quantity: 1, room_numbers: [ "102" ])

    result = described_class.call(room_type: room_type)

    expect(result).not_to be_success
    expect(result.error).to include("an active booking")
    expect(protected_room.reload.archived_at).to be_nil
    expect(kept_room.reload.position).to eq(1)
  end

  it "raises its service error from call bang" do
    other_type = create(:room_type, hotel: hotel, quantity: 1, room_numbers: [ "101" ])
    create(:room, hotel: hotel, room_type: other_type, number: "101")

    expect { described_class.call!(room_type: room_type) }
      .to raise_error(described_class::Error, "Room 101 already belongs to another room category.")
  end

  it "returns active rooms from call bang" do
    rooms = described_class.call!(room_type: room_type)

    expect(rooms.map(&:number)).to eq(%w[101 102])
  end
end
