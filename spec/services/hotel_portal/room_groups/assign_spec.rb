# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::RoomGroups::Assign do
  let(:hotel) { create(:hotel) }

  it "moves selected categories and preserves unrelated target members" do
    target = create(:room_group, hotel: hotel)
    existing_member = create(:room_type, hotel: hotel, room_group: target)
    moving_room = create(:room_type, hotel: hotel, room_group: create(:room_group, hotel: hotel))
    form = HotelPortal::RoomGroupAssignmentForm.new(
      room_group_id: target.id,
      room_type_ids: [ moving_room.id ]
    )

    result = described_class.call(hotel: hotel, form: form)

    expect(result).to be_success
    expect(moving_room.reload.room_group).to eq(target)
    expect(existing_member.reload.room_group).to eq(target)
  end

  it "creates the selected new group and assigns categories transactionally" do
    room_type = create(:room_type, hotel: hotel, room_group: nil)
    form = HotelPortal::RoomGroupAssignmentForm.new(
      room_group_id: "new",
      new_group_name: "Garden Wing",
      room_type_ids: [ room_type.id ]
    )

    result = described_class.call(hotel: hotel, form: form)

    expect(result).to be_success
    expect(result.room_group.name).to eq("Garden Wing")
    expect(room_type.reload.room_group).to eq(result.room_group)
  end

  it "rejects categories outside the hotel" do
    target = create(:room_group, hotel: hotel)
    foreign_room = create(:room_type)
    form = HotelPortal::RoomGroupAssignmentForm.new(
      room_group_id: target.id,
      room_type_ids: [ foreign_room.id ]
    )

    result = described_class.call(hotel: hotel, form: form)

    expect(result).not_to be_success
    expect(form.errors[:room_type_ids]).to be_present
    expect(foreign_room.reload.room_group).to be_nil
  end
end
