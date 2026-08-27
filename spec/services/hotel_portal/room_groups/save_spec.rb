# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::RoomGroups::Save do
  let(:hotel) { create(:hotel) }

  it "creates a group with rooms from multiple room categories" do
    first_type = create(:room_type, hotel: hotel)
    second_type = create(:room_type, hotel: hotel)
    first_room = create(:room, hotel: hotel, room_type: first_type, number: "101")
    second_room = create(:room, hotel: hotel, room_type: second_type, number: "201")

    result = described_class.call(
      hotel: hotel,
      attributes: { name: "Main Tower", room_ids: [ first_room.id, second_room.id ] }
    )

    expect(result).to be_success
    expect(result.room_group).to be_persisted
    expect(result.room_group.name).to eq("Main Tower")
    expect(result.room_group.active_rooms).to contain_exactly(first_room, second_room)
  end

  it "renames a group and replaces its active room membership" do
    group = create(:room_group, hotel: hotel, name: "Old Wing")
    room_type = create(:room_type, hotel: hotel)
    removed_room = create(:room, hotel: hotel, room_type: room_type, room_group: group, number: "101")
    kept_room = create(:room, hotel: hotel, room_type: room_type, room_group: group, number: "102")
    added_room = create(:room, hotel: hotel, room_type: room_type, number: "103")

    result = described_class.call(
      hotel: hotel,
      room_group: group,
      attributes: { name: "Garden Wing", room_ids: [ kept_room.id, added_room.id ] }
    )

    expect(result).to be_success
    expect(group.reload.name).to eq("Garden Wing")
    expect(kept_room.reload.room_group).to eq(group)
    expect(added_room.reload.room_group).to eq(group)
    expect(removed_room.reload).to be_active
    expect(removed_room.room_group).to be_nil
  end

  it "rejects a room assigned to another group" do
    group = create(:room_group, hotel: hotel)
    other_group = create(:room_group, hotel: hotel)
    room = create(:room, hotel: hotel, room_type: create(:room_type, hotel: hotel), room_group: other_group)

    result = described_class.call(
      hotel: hotel,
      room_group: group,
      attributes: { name: group.name, room_ids: [ room.id ] }
    )

    expect(result).not_to be_success
    expect(result.room_group.errors[:rooms]).to include("include one or more rooms assigned to another room group.")
    expect(room.reload.room_group).to eq(other_group)
  end

  it "preserves archived room membership" do
    group = create(:room_group, hotel: hotel)
    room_type = create(:room_type, hotel: hotel)
    archived_room = create(
      :room,
      hotel: hotel,
      room_type: room_type,
      room_group: group,
      archived_at: 1.day.ago
    )

    result = described_class.call(hotel: hotel, room_group: group, attributes: { name: group.name, room_ids: [] })

    expect(result).to be_success
    expect(archived_room.reload.room_group).to eq(group)
  end

  it "rejects malformed, archived, missing, and cross-property rooms" do
    group = create(:room_group, hotel: hotel)
    room_type = create(:room_type, hotel: hotel)
    archived_room = create(:room, hotel: hotel, room_type: room_type, archived_at: 1.day.ago)
    foreign_room = create(:room)

    [ "invalid", archived_room.id, foreign_room.id, Room.maximum(:id).to_i + 100 ].each do |room_id|
      result = described_class.call(
        hotel: hotel,
        room_group: group,
        attributes: { name: "Changed", room_ids: [ room_id ] }
      )

      expect(result).not_to be_success
      expect(result.room_group.errors[:rooms]).to be_present
      expect(group.reload.name).not_to eq("Changed")
    end
  end

  it "rolls back membership when the group name is invalid" do
    group = create(:room_group, hotel: hotel)
    room = create(:room, hotel: hotel, room_type: create(:room_type, hotel: hotel))

    result = described_class.call(
      hotel: hotel,
      room_group: group,
      attributes: { name: "", room_ids: [ room.id ] }
    )

    expect(result).not_to be_success
    expect(room.reload.room_group).to be_nil
  end

  it "returns the model errors for invalid attributes" do
    result = described_class.call(hotel: hotel, attributes: { name: "", room_ids: [] })

    expect(result).not_to be_success
    expect(result.room_group.errors[:name]).to be_present
  end

  it "returns a name error for a concurrent duplicate" do
    group = hotel.room_groups.build
    allow(group).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)

    result = described_class.call(
      hotel: hotel,
      room_group: group,
      attributes: { name: "Main Tower", room_ids: [] }
    )

    expect(result).not_to be_success
    expect(result.room_group.errors[:name]).to include("has already been taken")
  end
end
