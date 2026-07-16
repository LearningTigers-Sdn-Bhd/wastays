# frozen_string_literal: true

require "rails_helper"

RSpec.describe "StayView projection" do
  let(:window) do
    hotel = create(:hotel, accounting_business_date: Date.new(2026, 7, 16))
    StayView::DateWindow.new(hotel:, start_date: "2026-07-16", days: 7)
  end
  let(:capabilities) do
    StayView::Capabilities.new(**StayView::Capabilities.members.index_with { false }.merge(view_board: true, view_booking: true))
  end
  let(:booking_record) do
    StayView::BookingRecord.new(
      booking_room_id: 11,
      booking_id: 7,
      room_type_id: 3,
      room_number: "101",
      status: :confirmed,
      guest_name: "Ada Lovelace",
      check_in: Date.new(2026, 7, 16),
      check_out: Date.new(2026, 7, 17)
    )
  end

  it "projects one-night arrival and departure events using checkout-exclusive occupancy" do
    arrival = StayView::ResolveOccupancy.call(date: Date.new(2026, 7, 16), bookings: [ booking_record ])
    departure = StayView::ResolveOccupancy.call(date: Date.new(2026, 7, 17), bookings: [ booking_record ])
    after_departure = StayView::ResolveOccupancy.call(date: Date.new(2026, 7, 18), bookings: [ booking_record ])

    expect(arrival.map(&:state)).to eq([ :arrival ])
    expect(departure.map(&:state)).to eq([ :departure ])
    expect(after_departure.map(&:state)).to eq([ :available ])
  end

  it "supports a departure and another arrival in the same room on one date" do
    arriving = booking_record.with(booking_room_id: 12, booking_id: 8, check_in: Date.new(2026, 7, 17), check_out: Date.new(2026, 7, 19))

    occupancies = StayView::ResolveOccupancy.call(date: Date.new(2026, 7, 17), bookings: [ booking_record, arriving ])

    expect(occupancies.map(&:state)).to contain_exactly(:departure, :arrival)
    expect(occupancies).to be_frozen
  end

  it "projects clipped booking geometry and redacts guest identity" do
    clipped = booking_record.with(check_in: Date.new(2026, 7, 14), check_out: Date.new(2026, 7, 24))
    redacted = capabilities.with(view_booking: false)

    segment = StayView::ProjectBooking.call(booking: clipped, room_type_name: "Deluxe", date_window: window, capabilities: redacted)

    expect(segment.start_track).to eq(1)
    expect(segment.end_track).to eq(15)
    expect(segment).to be_clipped_left
    expect(segment).to be_clipped_right
    expect(segment.guest_label).to eq("Reserved")
    expect(segment.accessible_label).not_to include("Ada Lovelace")
  end

  it "projects inclusive room blocks as full-day half-open segments without SQL" do
    room_type = StayView::RoomTypeRecord.new(id: 3, name: "Deluxe", room_numbers: [ "101" ], smoking_allowed: false, pets_allowed: false)
    block = StayView::RoomBlockRecord.new(
      id: 4, room_type_id: 3, room_number: "101", block_type: :maintenance,
      reason: "Repairs", start_date: Date.new(2026, 7, 17), end_date: Date.new(2026, 7, 18)
    )
    sql = []
    subscriber = lambda { |_name, _start, _finish, _id, payload| sql << payload[:sql] unless payload[:cached] }
    current_window = window

    row = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      StayView::ProjectRoom.call(
        room_type:, room_number: "101", bookings: [ booking_record ], room_status: nil,
        room_blocks: [ block ], date_window: current_window, capabilities:
      )
    end

    segment = row.operational_segments.first
    expect(sql).to be_empty
    expect(segment.start_date).to eq(Date.new(2026, 7, 17))
    expect(segment.end_date).to eq(Date.new(2026, 7, 19))
    expect(segment.start_track).to eq(3)
    expect(segment.end_track).to eq(7)
    expect(row.current_physical_status).to eq(:ready)
  end

  it "separates late checkout detection from physical readiness" do
    status = StayView::RoomStatusRecord.new(
      room_type_id: 3, room_number: "101", status: :late_checkout_detected,
      priority: true, dnd: true, dnd_date: Date.new(2026, 7, 16)
    )

    result = StayView::ResolveCurrentRoomStatus.call(room_status: status, operational_date: Date.new(2026, 7, 16))

    expect(result.physical_status).to be_nil
    expect(result.operational_flags).to eq(priority: true, dnd: true, late_checkout: true)
    expect(result.operational_flags).to be_frozen
  end
end
