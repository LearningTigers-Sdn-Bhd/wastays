# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::NumberingContext do
  let(:hotel) { create(:hotel) }

  it "returns hotel-wide reserved numbers and the next numeric number" do
    first = create(:room_type, hotel:, quantity: 2, room_numbers: %w[101 A-1])
    create(:room, hotel:, room_type: first, number: "305", archived_at: 1.day.ago)

    result = described_class.call(hotel:)

    expect(result.reserved_numbers).to contain_exactly("101", "305", "A-1")
    expect(result.suggested_start).to eq(306)
  end

  it "ignores the current room type and preserves case-sensitive values" do
    current = create(:room_type, hotel:, quantity: 2, room_numbers: %w[101 A-1])
    create(:room, hotel:, room_type: current, number: "ARCHIVED", archived_at: 1.day.ago)
    other = create(:room_type, hotel:, quantity: 2, room_numbers: %w[201 a-1])
    create(:room, hotel:, room_type: other, number: "202")

    result = described_class.call(hotel:, room_type: current)

    expect(result.reserved_numbers).to contain_exactly("201", "202", "a-1")
    expect(result.reserved_numbers).not_to include("101", "A-1", "ARCHIVED")
    expect(result.suggested_start).to eq(203)
  end

  it "uses 101 when the hotel has no numeric room numbers" do
    create(:room_type, hotel:, quantity: 1, room_numbers: [ "Villa-A" ])

    expect(described_class.call(hotel:).suggested_start).to eq(101)
  end

  it "normalizes legacy JSON values" do
    room_type = create(:room_type, hotel:, quantity: 1, room_numbers: [])
    room_type.update_column(:room_numbers, [ " 101 " ])

    expect(described_class.call(hotel:).reserved_numbers).to eq([ "101" ])
  end
end
