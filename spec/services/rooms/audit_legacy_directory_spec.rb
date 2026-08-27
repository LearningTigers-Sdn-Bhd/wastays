# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::AuditLegacyDirectory do
  it "reports malformed room-number data without changing it" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel:, quantity: 3, room_numbers: [])
    raw_numbers = [ " 101", "101", " " ]
    room_type.update_column(:room_numbers, raw_numbers)

    result = described_class.new(room_types: RoomType.where(id: room_type.id)).call

    expect(result).not_to be_success
    expect(result.blocking_issues.map(&:code)).to contain_exactly(
      :blank_room_number,
      :untrimmed_room_number,
      :duplicate_room_number,
      :quantity_mismatch
    )
    expect(room_type.reload[:room_numbers]).to eq(raw_numbers)
  end

  it "reports every invalid numbered-room finding as blocking" do
    hotel = create(:hotel)
    blank = create(:room_type, hotel:, quantity: 2, room_numbers: [])
    blank.update_column(:room_numbers, [ "101", " " ])
    duplicate = create(:room_type, hotel:, quantity: 2, room_numbers: [])
    duplicate.update_column(:room_numbers, [ "201", "201" ])
    short = create(:room_type, hotel:, quantity: 2, room_numbers: [])
    short.update_column(:room_numbers, [ "301" ])

    result = described_class.new(room_types: hotel.room_types).call

    expect(result.blocking_issues.map(&:code)).to include(
      :blank_room_number,
      :duplicate_room_number,
      :quantity_mismatch
    )
  end

  it "reports normalized room numbers that belong to different room types" do
    hotel = create(:hotel)
    first = create(:room_type, hotel:, name: "Deluxe", quantity: 1, room_numbers: [ "101" ])
    second = create(:room_type, hotel:, name: "Suite", quantity: 1, room_numbers: [])
    second.update_column(:room_numbers, [ " 101 " ])

    result = described_class.new(room_types: RoomType.where(id: [ first.id, second.id ])).call

    duplicates = result.blocking_issues.select { |issue| issue.code == :cross_room_type_duplicate }
    expect(duplicates.map(&:room_type_id)).to contain_exactly(first.id, second.id)
    expect(duplicates.map(&:room_number).uniq).to eq([ "101" ])
  end

  it "does not compare room numbers between hotels" do
    first = create(:room_type, quantity: 1, room_numbers: [ "101" ])
    second = create(:room_type, quantity: 1, room_numbers: [ "101" ])

    result = described_class.new(room_types: RoomType.where(id: [ first.id, second.id ])).call

    expect(result).to be_success
  end

  it "accepts quantity-only room types" do
    room_type = create(:room_type, quantity: 5, room_numbers: [])

    result = described_class.new(room_types: RoomType.where(id: room_type.id)).call

    expect(result).to be_success
  end
end
