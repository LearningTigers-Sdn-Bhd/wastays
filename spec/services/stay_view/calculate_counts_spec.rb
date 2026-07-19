# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::CalculateCounts do
  let(:reference_date) { Date.new(2026, 7, 16) }
  let(:capabilities) do
    StayView::Capabilities.new(**StayView::Capabilities.members.index_with { false })
  end

  it "returns every mutually exclusive operational count, including zero values" do
    room = room_row(room_number: "101")
    group = StayView::RoomGroup.new(room_type_id: 3, name: "Deluxe", rooms: [ room ])

    counts = described_class.call(
      room_groups: [ group ],
      room_card_presentations: { room.key => presentation(:vacant) },
      reference_date:
    )

    expect(counts.reference_date).to eq(reference_date)
    expect(counts.room_states).to eq(
      all: 1,
      vacant: 1,
      arrival: 0,
      occupied: 0,
      departure: 0,
      turnover: 0,
      blocked: 0,
      dirty: 0
    )
  end

  it "counts every room once operationally while keeping dirty supplemental" do
    states = StayView::ROOM_CARD_STATES
    rooms = states.each_with_index.map do |state, index|
      room_row(room_number: (101 + index).to_s, physical_status: (state == :arrival ? :dirty : :ready))
    end
    group = StayView::RoomGroup.new(room_type_id: 3, name: "Deluxe", rooms:)
    presentations = rooms.zip(states).to_h { |room, state| [ room.key, presentation(state) ] }

    counts = described_class.call(room_groups: [ group ], room_card_presentations: presentations, reference_date:)

    expect(counts.room_states).to eq(
      all: 6,
      vacant: 1,
      arrival: 1,
      occupied: 1,
      departure: 1,
      turnover: 1,
      blocked: 1,
      dirty: 1
    )
  end

  private

  def presentation(state)
    StayView::ResolveRoomCardSlots::Result.new(
      departure: nil,
      current_booking: nil,
      current_block: nil,
      state:
    )
  end

  def room_row(room_number:, physical_status: :ready)
    StayView::RoomRow.new(
      key: "3:#{room_number}",
      dom_id: "room-#{room_number}",
      room_number:,
      room_type_id: 3,
      room_type_name: "Deluxe",
      smoking_allowed: false,
      pets_allowed: false,
      current_physical_status: physical_status,
      operational_flags: {},
      day_cells: [],
      booking_segments: [],
      operational_segments: [],
      housekeeping_alerts: [],
      capabilities:
    )
  end
end
