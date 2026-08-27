# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::SaveSeedRoomType do
  let(:hotel) { create(:hotel) }
  let(:attributes) do
    {
      name: "Seeded Suite",
      description: "A seeded room category.",
      quantity: 2,
      base_price: 200,
      max_adults: 2,
      max_children: 1,
      room_number_mode: "custom",
      room_numbers: %w[101 102]
    }
  end

  it "creates a seeded room type and its physical rooms atomically" do
    room_type = described_class.call!(hotel:, attributes:)

    expect(room_type.room_numbers).to eq(%w[101 102])
    expect(room_type.rooms.active.ordered.pluck(:number, :position)).to eq([ [ "101", 0 ], [ "102", 1 ] ])
  end

  it "updates a repeated seed without recreating unchanged rooms" do
    room_type = described_class.call!(hotel:, attributes:)
    original_ids = room_type.rooms.ordered.ids

    updated = described_class.call!(hotel:, attributes: attributes.merge(base_price: 225))

    expect(updated.id).to eq(room_type.id)
    expect(updated.base_price).to eq(225)
    expect(updated.rooms.ordered.ids).to eq(original_ids)
  end

  it "rolls the seed write back when a room number belongs to another category" do
    other_type = create(:room_type, hotel:, quantity: 1, room_numbers: [ "102" ])
    create(:room, hotel:, room_type: other_type, number: "102")

    expect {
      described_class.call!(hotel:, attributes:)
    }.to raise_error(Rooms::SyncFromRoomType::Error, "Room 102 already belongs to another room category.")

    expect(hotel.room_types.find_by(name: "Seeded Suite")).to be_nil
    expect(Room.where(hotel:, number: "101")).to be_empty
  end
end
