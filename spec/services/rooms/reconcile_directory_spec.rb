# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::ReconcileDirectory do
  it "reports a reconciled directory with summary counts" do
    hotel = create(:hotel)
    group = create(:room_group, hotel:)
    room_type = create(:room_type, hotel:, room_group: group, quantity: 2, room_numbers: %w[101 102])
    create(:room, hotel:, room_type:, room_group: group, number: "101", position: 0)
    create(:room, hotel:, room_type:, room_group: group, number: "102", position: 1)

    result = described_class.call(hotel:)

    expect(result).to be_reconciled
    expect(result.summary).to include(expected_rooms: 2, active_rooms: 2, archived_rooms: 0, issues: 0)
  end

  it "accepts quantity-only room types with no physical rooms" do
    hotel = create(:hotel)
    create(:room_type, hotel:, quantity: 3, room_numbers: [])

    result = described_class.call(hotel:)

    expect(result).to be_reconciled
    expect(result.summary[:expected_rooms]).to eq(0)
  end

  it "reports all source data issue types" do
    hotel = create(:hotel)
    first = create(:room_type, hotel:, quantity: 4, room_numbers: [])
    second = create(:room_type, hotel:, quantity: 1, room_numbers: [ "101" ])
    first.update_column(:room_numbers, [ " ", " 101 ", "101" ])

    result = described_class.call(hotel:)

    expect(result.issues.map(&:type)).to include(
      :blank_number,
      :untrimmed_number,
      :duplicate_json_number,
      :duplicate_hotel_number,
      :quantity_mismatch
    )
    expect(result.summary[:issue_counts][:duplicate_hotel_number]).to eq(1)
    expect(result.issues.find { |issue| issue.type == :duplicate_hotel_number }.actual[:room_type_ids])
      .to contain_exactly(first.id, second.id)
  end

  it "reports missing, unexpected, archived, and mismatched directory rows" do
    hotel = create(:hotel)
    expected_group = create(:room_group, hotel:)
    wrong_group = create(:room_group, hotel:)
    expected_type = create(
      :room_type,
      hotel:,
      room_group: expected_group,
      quantity: 5,
      room_numbers: %w[101 102 103 104 105]
    )
    wrong_type = create(:room_type, hotel:)

    create(:room, hotel:, room_type: expected_type, room_group: expected_group, number: "102", position: 1, archived_at: Time.current)
    create(:room, hotel:, room_type: wrong_type, room_group: expected_group, number: "103", position: 2)
    create(:room, hotel:, room_type: expected_type, room_group: wrong_group, number: "104", position: 3)
    create(:room, hotel:, room_type: expected_type, room_group: expected_group, number: "105", position: 8)
    create(:room, hotel:, room_type: wrong_type, number: "999", position: 0)

    result = described_class.call(hotel:)

    expect(result.issues.map(&:type)).to include(
      :missing_room,
      :unexpected_active_room,
      :expected_room_archived,
      :wrong_room_type,
      :wrong_room_group,
      :wrong_position
    )
  end

  it "reports a room whose hotel differs from its room type hotel" do
    hotel = create(:hotel)
    room_type = create(:room_type, hotel:, quantity: 1, room_numbers: [ "101" ])
    foreign_hotel = create(:hotel)
    room = create(:room, hotel:, room_type:, number: "101")
    room.update_column(:hotel_id, foreign_hotel.id)

    result = described_class.call(hotel:)

    expect(result.issues.map(&:type)).to include(:wrong_hotel, :missing_room)
  end
end
