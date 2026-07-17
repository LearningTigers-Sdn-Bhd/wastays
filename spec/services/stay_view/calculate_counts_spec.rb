# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::CalculateCounts do
  let(:reference_date) { Date.new(2026, 7, 16) }
  let(:capabilities) do
    StayView::Capabilities.new(**StayView::Capabilities.members.index_with { false })
  end

  it "returns every operational count, including zero values" do
    room = room_row(room_number: "101")
    group = StayView::RoomGroup.new(room_type_id: 3, name: "Deluxe", rooms: [ room ])

    counts = described_class.call(
      room_groups: [ group ],
      reference_date:,
      operational_date: reference_date
    )

    expect(counts.reference_date).to eq(reference_date)
    expect(counts.room_states).to eq(
      all: 1,
      vacant: 1,
      occupied: 0,
      reserved: 0,
      blocked: 0,
      due_out: 0,
      dirty: 0
    )
  end

  it "counts filtered rooms once per state while allowing dirty and due out to overlap" do
    reserved = room_row(
      room_number: "101",
      physical_status: :dirty,
      booking_segments: [ booking_segment(id: 1, status: :confirmed, check_out: reference_date + 1.day) ]
    )
    occupied = room_row(
      room_number: "102",
      booking_segments: [ booking_segment(id: 2, status: :checked_in, check_out: reference_date + 1.day) ]
    )
    blocked = room_row(
      room_number: "103",
      operational_segments: [ operational_segment ]
    )
    due_out = room_row(
      room_number: "104",
      booking_segments: [ booking_segment(id: 4, status: :review_due_out, check_out: reference_date) ]
    )
    late_checkout = room_row(room_number: "105", operational_flags: { late_checkout: true })
    vacant = room_row(room_number: "106")
    group = StayView::RoomGroup.new(
      room_type_id: 3,
      name: "Deluxe",
      rooms: [ reserved, occupied, blocked, due_out, late_checkout, vacant ]
    )

    counts = described_class.call(
      room_groups: [ group ],
      reference_date:,
      operational_date: reference_date
    )

    expect(counts.room_states).to eq(
      all: 6,
      vacant: 1,
      occupied: 1,
      reserved: 1,
      blocked: 1,
      due_out: 2,
      dirty: 1
    )
  end

  it "does not apply the current late-checkout flag to another reference date" do
    room = room_row(room_number: "101", operational_flags: { late_checkout: true })
    group = StayView::RoomGroup.new(room_type_id: 3, name: "Deluxe", rooms: [ room ])

    counts = described_class.call(
      room_groups: [ group ],
      reference_date: reference_date + 1.day,
      operational_date: reference_date
    )

    expect(counts.due_out).to eq(0)
    expect(counts.vacant).to eq(1)
  end

  private

  def room_row(room_number:, physical_status: :ready, operational_flags: {}, booking_segments: [], operational_segments: [])
    StayView::RoomRow.new(
      key: "3:#{room_number}",
      dom_id: "room-#{room_number}",
      room_number:,
      room_type_id: 3,
      room_type_name: "Deluxe",
      smoking_allowed: false,
      pets_allowed: false,
      current_physical_status: physical_status,
      operational_flags:,
      day_cells: [ StayView::DayCell.new(
        date: reference_date,
        occupancies: [ StayView::Occupancy.new(state: :available, label: "Available") ]
      ) ],
      booking_segments:,
      operational_segments:,
      capabilities:
    )
  end

  def booking_segment(id:, status:, check_out:)
    StayView::BookingSegment.new(
      dom_id: "booking-#{id}",
      booking_id: id,
      booking_room_id: id,
      guest_label: "Guest #{id}",
      status:,
      check_in: reference_date - 1.day,
      check_out:,
      start_track: 1,
      end_track: 2,
      clipped_left: false,
      clipped_right: false,
      accessible_label: "Guest #{id}",
      capabilities:
    )
  end

  def operational_segment
    StayView::OperationalSegment.new(
      dom_id: "block-1",
      room_block_id: 1,
      kind: :maintenance,
      label: "Maintenance",
      start_date: reference_date,
      end_date: reference_date + 1.day,
      start_track: 1,
      end_track: 3,
      clipped_left: false,
      clipped_right: false,
      accessible_label: "Maintenance",
      capabilities:
    )
  end
end
