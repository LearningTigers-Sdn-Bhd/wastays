# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rooms::GroupAssignmentsQuery do
  let(:hotel) { create(:hotel) }
  let(:room_type) { create(:room_type, hotel:) }
  let(:other_room_type) { create(:room_type, hotel:) }
  let(:main_wing) { create(:room_group, hotel:, name: "Main Wing") }
  let(:annexe) { create(:room_group, hotel:, name: "Annexe") }

  it "keys each assignment by room type and room number" do
    create(:room, hotel:, room_type:, room_group: main_wing, number: "101")

    result = described_class.call(hotel:)

    expect(result.name_for(room_type.id, "101")).to eq("Main Wing")
    expect(result.id_for(room_type.id, "101")).to eq(main_wing.id)
  end

  it "reports an unassigned room as ungrouped" do
    create(:room, hotel:, room_type:, number: "102")

    result = described_class.call(hotel:)

    expect(result.for(room_type.id, "102")).to be_nil
    expect(result.name_for(room_type.id, "102")).to eq("Ungrouped")
  end

  it "reports a room number without a room record as ungrouped" do
    result = described_class.call(hotel:)

    expect(result.name_for(room_type.id, "999")).to eq("Ungrouped")
  end

  it "skips archived rooms" do
    create(:room, hotel:, room_type:, room_group: main_wing, number: "103", archived_at: Time.current)

    result = described_class.call(hotel:)

    expect(result.for(room_type.id, "103")).to be_nil
  end

  it "skips rooms that belong to another hotel" do
    other_hotel = create(:hotel)
    other_hotel_room_type = create(:room_type, hotel: other_hotel)
    other_group = create(:room_group, hotel: other_hotel, name: "Far Wing")
    create(:room, hotel: other_hotel, room_type: other_hotel_room_type, room_group: other_group, number: "101")

    result = described_class.call(hotel:)

    expect(result.assignments).to be_empty
    expect(result.options).to be_empty
  end

  it "lists each group once, ordered by name" do
    create(:room, hotel:, room_type:, room_group: main_wing, number: "201")
    create(:room, hotel:, room_type: other_room_type, room_group: main_wing, number: "202")
    create(:room, hotel:, room_type:, room_group: annexe, number: "203")

    result = described_class.call(hotel:)

    expect(result.options.map(&:name)).to eq([ "Annexe", "Main Wing" ])
  end

  it "spans room types inside one group" do
    create(:room, hotel:, room_type:, room_group: main_wing, number: "301")
    create(:room, hotel:, room_type: other_room_type, room_group: main_wing, number: "401")

    result = described_class.call(hotel:)

    expect(result.name_for(room_type.id, "301")).to eq("Main Wing")
    expect(result.name_for(other_room_type.id, "401")).to eq("Main Wing")
  end
end
