# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::ResolveRoomCardSlots do
  let(:hotel) { instance_double(Hotel, id: 9) }
  let(:capabilities) do
    StayView::Capabilities.new(**StayView::Capabilities.members.index_with { false })
  end
  let(:date) { Date.new(2026, 7, 16) }

  def booking_segment(id:, check_in:, check_out:, status: :confirmed, actual_check_in: nil, actual_check_out: nil)
    StayView::BookingSegment.new(
      dom_id: "booking-#{id}", booking_id: id, booking_room_id: id,
      guest_label: "Guest #{id}", status:, check_in:, check_out:,
      actual_check_in:, actual_check_out:,
      start_track: 1, end_track: 2, clipped_left: false, clipped_right: false,
      accessible_label: "Guest #{id}", capabilities:
    )
  end

  def block_segment(id:)
    StayView::OperationalSegment.new(
      dom_id: "block-#{id}", room_block_id: id, kind: :maintenance,
      label: "Maintenance", start_date: date, end_date: date + 1.day,
      start_track: 1, end_track: 3, clipped_left: false, clipped_right: false,
      accessible_label: "Maintenance block", capabilities:
    )
  end

  def room(bookings:, blocks: [])
    StayView::RoomRow.new(
      key: "3:101", dom_id: "room-101", room_number: "101", room_type_id: 3,
      room_type_name: "Deluxe", smoking_allowed: false, pets_allowed: false,
      current_physical_status: :ready, operational_flags: {}, day_cells: [],
      booking_segments: bookings, operational_segments: blocks, housekeeping_alerts: [], capabilities:
    )
  end

  it "separates an outgoing stay from an arriving current stay" do
    departure = booking_segment(id: 1, check_in: date - 2.days, check_out: date)
    arrival = booking_segment(id: 2, check_in: date, check_out: date + 2.days)

    result = described_class.call(hotel:, room: room(bookings: [ departure, arrival ]), date:)

    expect(result).to have_attributes(departure:, current_booking: arrival, current_block: nil, state: :turnover)
  end

  it "places a zero-night stay only in the current slot" do
    zero_night = booking_segment(id: 3, check_in: date, check_out: date)

    result = described_class.call(hotel:, room: room(bookings: [ zero_night ]), date:)

    expect(result).to have_attributes(departure: nil, current_booking: zero_night, current_block: nil, state: :arrival)
  end

  it "gives an active block precedence and logs conflicting candidate identifiers" do
    occupied = booking_segment(id: 5, check_in: date - 1.day, check_out: date + 1.day)
    arrival = booking_segment(id: 4, check_in: date, check_out: date + 2.days)
    block = block_segment(id: 8)
    allow(Rails.logger).to receive(:warn)

    result = described_class.call(hotel:, room: room(bookings: [ occupied, arrival ], blocks: [ block ]), date:)

    expect(result).to have_attributes(departure: nil, current_booking: nil, current_block: block, state: :blocked)
    expect(Rails.logger).to have_received(:warn) do |message|
      payload = JSON.parse(message)
      expect(payload).to include(
        "event" => "stay_view.room_card_slot_conflict",
        "hotel_id" => 9,
        "room_key" => "3:101",
        "current_booking_ids" => [ 5, 4 ],
        "current_block_ids" => [ 8 ]
      )
    end
  end

  it "selects an arrival before an overlapping occupied stay deterministically" do
    occupied = booking_segment(id: 2, check_in: date - 1.day, check_out: date + 1.day)
    arrival = booking_segment(id: 7, check_in: date, check_out: date + 2.days)
    allow(Rails.logger).to receive(:warn)

    result = described_class.call(hotel:, room: room(bookings: [ occupied, arrival ]), date:)

    expect(result.current_booking).to eq(arrival)
    expect(Rails.logger).to have_received(:warn)
  end

  it "classifies a checked-in current stay as occupied" do
    occupied = booking_segment(
      id: 9,
      status: :checked_in,
      check_in: date - 1.day,
      check_out: date + 1.day
    )

    result = described_class.call(hotel:, room: room(bookings: [ occupied ]), date:)

    expect(result).to have_attributes(current_booking: occupied, state: :occupied)
  end

  it "classifies a departure without an incoming stay as departure" do
    departure = booking_segment(id: 10, check_in: date - 1.day, check_out: date)

    result = described_class.call(hotel:, room: room(bookings: [ departure ]), date:)

    expect(result).to have_attributes(departure:, current_booking: nil, state: :departure)
  end

  it "keeps an overdue checked-in stay occupied only on the operational date" do
    overdue = booking_segment(
      id: 11,
      status: :review_due_out,
      check_in: date - 3.days,
      check_out: date - 1.day
    )

    current = described_class.call(hotel:, room: room(bookings: [ overdue ]), date:, operational_date: date)
    future = described_class.call(
      hotel:,
      room: room(bookings: [ overdue ]),
      date: date + 1.day,
      operational_date: date
    )

    expect(current).to have_attributes(current_booking: overdue, state: :occupied)
    expect(future).to have_attributes(current_booking: nil, state: :vacant)
  end

  it "classifies a room without activity as vacant" do
    result = described_class.call(hotel:, room: room(bookings: []), date:)

    expect(result.state).to eq(:vacant)
  end

  it "uses actual lifecycle dates for historical arrival, occupancy, and departure" do
    actual_arrival = date - 2.days
    completed = booking_segment(
      id: 12,
      status: :completed,
      check_in: actual_arrival,
      check_out: date - 1.day,
      actual_check_in: actual_arrival,
      actual_check_out: date
    )
    projected_room = room(bookings: [ completed ])

    arrival = described_class.call(hotel:, room: projected_room, date: actual_arrival, operational_date: date)
    occupied = described_class.call(hotel:, room: projected_room, date: date - 1.day, operational_date: date)
    departure = described_class.call(hotel:, room: projected_room, date:, operational_date: date)

    expect(arrival).to have_attributes(state: :arrival, current_booking: completed)
    expect(occupied).to have_attributes(state: :occupied, current_booking: completed)
    expect(departure).to have_attributes(state: :departure, departure: completed, current_booking: nil)
  end
end
