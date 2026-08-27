# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::BuildRoomSections do
  let(:date) { Date.new(2026, 8, 27) }

  def room(number, room_type_id:, room_type_name:, room_group_id: nil, room_group_name: nil)
    StayView::RoomRow.new(
      key: "#{room_type_id}:#{number}",
      dom_id: "stay_view_room_#{room_type_id}_#{number}",
      room_number: number,
      room_type_id:,
      room_type_name:,
      room_group_id:,
      room_group_name:,
      smoking_allowed: false,
      pets_allowed: false,
      current_physical_status: :ready,
      status_note: nil,
      priority_note: nil,
      operational_flags: {},
      day_cells: [],
      booking_segments: [],
      operational_segments: [],
      housekeeping_alerts: [],
      capabilities: nil
    )
  end

  let(:summary) do
    StayView::InventoryDateSummary.new(date:, sellable: 2, sold: 1, available: 1, occupancy: 50)
  end

  let(:deluxe_101) { room("101", room_type_id: 1, room_type_name: "Deluxe", room_group_id: 7, room_group_name: "Main Wing") }
  let(:deluxe_102) { room("102", room_type_id: 1, room_type_name: "Deluxe") }
  let(:suite_201) { room("201", room_type_id: 2, room_type_name: "Suite", room_group_id: 7, room_group_name: "Main Wing") }
  let(:suite_202) { room("202", room_type_id: 2, room_type_name: "Suite", room_group_id: 3, room_group_name: "Annexe") }

  let(:board) do
    instance_double(
      StayView::Board,
      room_groups: [
        StayView::RoomGroup.new(room_type_id: 1, name: "Deluxe", rooms: [ deluxe_101, deluxe_102 ],
                                inventory_summaries: [ summary ]),
        StayView::RoomGroup.new(room_type_id: 2, name: "Suite", rooms: [ suite_201, suite_202 ],
                                inventory_summaries: [ summary ])
      ]
    )
  end

  def sections(mode) = described_class.call(board:, mode:, date:)

  it "returns one section for each room type" do
    result = sections("room_type")

    expect(result.map(&:label)).to eq([ "Deluxe", "Suite" ])
    expect(result.map(&:size)).to eq([ 2, 2 ])
    expect(result.first.items.map { |item| item.room.room_number }).to eq(%w[101 102])
  end

  it "returns one flat section holding every room" do
    result = sections("none")

    expect(result.size).to eq(1)
    expect(result.first.items.map { |item| item.room.room_number }).to eq(%w[101 102 201 202])
  end

  it "returns one section for each room group, ungrouped last" do
    result = sections("room_group")

    expect(result.map(&:label)).to eq([ "Annexe", "Main Wing", "Ungrouped" ])
    expect(result.map(&:size)).to eq([ 1, 2, 1 ])
  end

  it "puts rooms of different room types in one room group" do
    main_wing = sections("room_group").find { |section| section.label == "Main Wing" }

    expect(main_wing.items.map { |item| item.room.room_type_name }).to eq([ "Deluxe", "Suite" ])
    expect(main_wing.room_group_id).to eq(7)
  end

  it "keeps the room-type inventory summary on each item" do
    result = sections("room_group")

    expect(result.flat_map(&:items)).to all(satisfy { |item| item.inventory_summary == summary })
  end

  it "shows each room one time in every mode" do
    numbers = described_class::MODES.map do |mode|
      sections(mode).flat_map { |section| section.items.map { |item| item.room.room_number } }.sort
    end

    expect(numbers).to all(eq(%w[101 102 201 202]))
  end

  it "falls back to grouping by room type when the mode is unknown" do
    expect(sections("nonsense").map(&:label)).to eq([ "Deluxe", "Suite" ])
  end

  it "returns no section when the board is empty" do
    empty_board = instance_double(StayView::Board, room_groups: [])

    expect(described_class::MODES.map { |mode| described_class.call(board: empty_board, mode:, date:) }).to all(be_empty)
  end
end
