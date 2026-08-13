# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::RoomGroups::Save do
  let(:hotel) { create(:hotel) }

  it "creates a valid room group" do
    result = described_class.call(hotel: hotel, attributes: { name: "Main Tower" })

    expect(result).to be_success
    expect(result.room_group).to be_persisted
    expect(result.room_group.name).to eq("Main Tower")
  end

  it "renames a group without changing category membership" do
    group = create(:room_group, hotel: hotel)
    room_type = create(:room_type, hotel: hotel, room_group: group)

    result = described_class.call(hotel: hotel, room_group: group, attributes: { name: "Garden Wing" })

    expect(result).to be_success
    expect(group.reload.name).to eq("Garden Wing")
    expect(room_type.reload.room_group).to eq(group)
  end

  it "returns the model errors for invalid attributes" do
    result = described_class.call(hotel: hotel, attributes: { name: "" })

    expect(result).not_to be_success
    expect(result.room_group.errors[:name]).to be_present
  end
end
