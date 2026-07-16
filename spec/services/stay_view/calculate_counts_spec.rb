# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::CalculateCounts do
  let(:capabilities) do
    StayView::Capabilities.new(**StayView::Capabilities.members.index_with { false })
  end

  it "counts only the room projection supplied after filtering" do
    occupancy = StayView::Occupancy.new(
      state: :arrival,
      booking_id: 7,
      booking_status: :confirmed,
      label: "Arrival"
    )
    segment = StayView::BookingSegment.new(
      dom_id: "booking-7",
      booking_id: 7,
      booking_room_id: 11,
      guest_label: "Ada",
      status: :confirmed,
      check_in: Date.new(2026, 7, 16),
      check_out: Date.new(2026, 7, 17),
      start_track: 2,
      end_track: 4,
      clipped_left: false,
      clipped_right: false,
      accessible_label: "Ada, confirmed",
      capabilities:
    )
    room = StayView::RoomRow.new(
      key: "3:101",
      dom_id: "room-101",
      room_number: "101",
      room_type_id: 3,
      room_type_name: "Deluxe",
      smoking_allowed: false,
      pets_allowed: false,
      current_physical_status: :dirty,
      operational_flags: {},
      day_cells: [ StayView::DayCell.new(date: Date.new(2026, 7, 16), occupancies: [ occupancy ]) ],
      booking_segments: [ segment ],
      operational_segments: [],
      capabilities:
    )
    group = StayView::RoomGroup.new(room_type_id: 3, name: "Deluxe", rooms: [ room ])

    counts = described_class.call(room_groups: [ group ])

    expect(counts.rooms).to eq(1)
    expect(counts.physical_statuses).to eq(dirty: 1)
    expect(counts.occupancies).to eq(arrival: 1)
    expect(counts.booking_statuses).to eq(confirmed: 1)
    expect(counts.operational_segments).to be_empty
  end
end
