# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::ProjectBooking do
  let(:window) do
    hotel = create(:hotel, accounting_business_date: Date.new(2026, 7, 16))
    StayView::DateWindow.new(hotel:, start_date: "2026-07-16", days: 7)
  end

  let(:capabilities) do
    StayView::Capabilities.new(
      **StayView::Capabilities.members.index_with { false }.merge(view_board: true, view_booking: false)
    )
  end

  it "projects clipped centre-aligned geometry and redacts guest identity" do
    booking = StayView::BookingRecord.new(
      booking_room_id: 11,
      booking_id: 7,
      room_type_id: 3,
      room_number: "101",
      status: :confirmed,
      guest_name: "Ada Lovelace",
      check_in: Date.new(2026, 7, 14),
      check_out: Date.new(2026, 7, 24),
      group_booking_id: 5,
      group_reference: "HTL-10000005",
      group_name: "Lovelace Conference",
      group_position: 2
    )

    segment = described_class.call(booking:, room_type_name: "Deluxe", date_window: window, capabilities:)

    expect(segment.start_track).to eq(1)
    expect(segment.end_track).to eq(15)
    expect(segment).to be_clipped_left
    expect(segment).to be_clipped_right
    expect(segment.guest_label).to eq("Reserved")
    expect(segment.accessible_label).not_to include("Ada Lovelace")
    expect(segment).to have_attributes(
      group_booking_id: 5,
      group_reference: nil,
      group_name: nil,
      group_position: 2,
      group_rooms: []
    )
  end

  it "projects immutable group display identity with booking permission" do
    booking = StayView::BookingRecord.new(
      booking_room_id: 11,
      booking_id: 7,
      room_type_id: 3,
      room_number: "101",
      status: :confirmed,
      guest_name: "Ada Lovelace",
      check_in: Date.new(2026, 7, 16),
      check_out: Date.new(2026, 7, 18),
      group_booking_id: 5,
      group_reference: "HTL-10000005",
      group_name: "Lovelace Conference",
      group_position: 2
    )

    group_rooms = [
      StayView::GroupRoomRecord.new(group_booking_id: 5, booking_id: 7, booking_room_id: 11, group_position: 2, room_number: "101", room_type_name: "Deluxe"),
      StayView::GroupRoomRecord.new(group_booking_id: 5, booking_id: 8, booking_room_id: 12, group_position: 3, room_number: "202", room_type_name: "Suite")
    ]
    segment = described_class.call(
      booking:,
      room_type_name: "Deluxe",
      group_rooms:,
      date_window: window,
      capabilities: capabilities.with(view_booking: true)
    )

    expect(segment).to have_attributes(
      group_booking_id: 5,
      group_reference: "HTL-10000005",
      group_name: "Lovelace Conference",
      group_position: 2,
      booking_type: :group,
      primary_guest_name: "Ada Lovelace"
    )
    expect(segment.group_rooms.map(&:room_number)).to eq([ "202" ])
    expect(segment).to be_frozen
    expect(segment.group_reference).to be_frozen
    expect(segment.group_name).to be_frozen
  end

  it "projects a humanized booking source only with booking permission" do
    booking = StayView::BookingRecord.new(
      booking_room_id: 11, booking_id: 7, room_type_id: 3, room_number: "101",
      status: :confirmed, guest_name: "Ada Lovelace",
      check_in: Date.new(2026, 7, 16), check_out: Date.new(2026, 7, 18),
      source: "walk_in"
    )

    permitted = described_class.call(booking:, room_type_name: "Deluxe", date_window: window, capabilities: capabilities.with(view_booking: true))
    expect(permitted.source_label).to eq("Walk-in")
    expect(permitted.accessible_label).to include("source Walk-in")

    redacted = described_class.call(booking:, room_type_name: "Deluxe", date_window: window, capabilities:)
    expect(redacted.source_label).to be_nil
    expect(redacted.accessible_label).not_to include("Walk-in")
  end

  it "maps a channel booking source to a concise label" do
    booking = StayView::BookingRecord.new(
      booking_room_id: 11, booking_id: 7, room_type_id: 3, room_number: "101",
      status: :confirmed, guest_name: "Ada Lovelace",
      check_in: Date.new(2026, 7, 16), check_out: Date.new(2026, 7, 18),
      source: "channel_manager"
    )

    segment = described_class.call(booking:, room_type_name: "Deluxe", date_window: window, capabilities: capabilities.with(view_booking: true))

    expect(segment.source_label).to eq("Channel")
  end

  it "projects pax and hotel-local boat times only with booking permission" do
    check_in_at = Time.utc(2026, 7, 16, 7)
    check_out_at = Time.utc(2026, 7, 18, 4)
    booking = StayView::BookingRecord.new(
      booking_room_id: 11, booking_id: 7, room_type_id: 3, room_number: "101",
      status: :confirmed, guest_name: "Ada Lovelace",
      check_in: Date.new(2026, 7, 16), check_out: Date.new(2026, 7, 18),
      check_in_at:, check_out_at:,
      adults: 2, children: 1,
      boat_in_at: Time.utc(2026, 7, 16, 7), boat_out_at: Time.utc(2026, 7, 18, 4)
    )

    permitted = described_class.call(
      booking:, room_type_name: "Deluxe", date_window: window,
      capabilities: capabilities.with(view_booking: true)
    )
    expect(permitted).to have_attributes(
      adults: 2, children: 1,
      check_in_at: check_in_at.in_time_zone(window.time_zone_name),
      check_out_at: check_out_at.in_time_zone(window.time_zone_name)
    )
    expect(permitted.boat_in_at.time_zone.name).to eq(window.time_zone_name)
    expect(permitted.accessible_label).to include(
      "2 adults, 1 children", "check-in 15:00", "check-out 12:00", "boat-in"
    )

    redacted = described_class.call(booking:, room_type_name: "Deluxe", date_window: window, capabilities:)
    expect(redacted).to have_attributes(
      adults: nil, children: nil, boat_in_at: nil, boat_out_at: nil,
      check_in_at: nil, check_out_at: nil
    )
    expect(redacted.accessible_label).not_to include("adults", "check-in", "check-out", "boat-in", "boat-out")
  end

  it "positions the bar on actual occupancy dates while keeping scheduled display dates" do
    actual_check_in_at = Time.zone.local(2026, 7, 16, 15, 5)
    actual_check_out_at = Time.zone.local(2026, 7, 19, 7, 55)
    booking = StayView::BookingRecord.new(
      booking_room_id: 11, booking_id: 7, room_type_id: 3, room_number: "101",
      status: :completed, guest_name: "Ada Lovelace",
      check_in: Date.new(2026, 7, 16), check_out: Date.new(2026, 7, 18),
      actual_check_in: Date.new(2026, 7, 16), actual_check_out: Date.new(2026, 7, 19),
      actual_check_in_at:, actual_check_out_at:
    )

    segment = described_class.call(
      booking:, room_type_name: "Deluxe", date_window: window,
      capabilities: capabilities.with(view_booking: true)
    )

    # Display fields stay scheduled, but a late checkout stretches the bar to
    # the actual departure day so it forms the same-day turnover the rooms view
    # already reports.
    expect(segment).to have_attributes(
      check_in: Date.new(2026, 7, 16),
      check_out: Date.new(2026, 7, 18),
      actual_check_in: Date.new(2026, 7, 16),
      actual_check_out: Date.new(2026, 7, 19),
      actual_check_in_at:,
      actual_check_out_at:
    )
    actual_tracks = window.booking_tracks(booking.actual_check_in, booking.actual_check_out)
    expect(segment.start_track).to eq(actual_tracks.start_track)
    expect(segment.end_track).to eq(actual_tracks.end_track)
    expect(segment.end_track).not_to eq(window.booking_tracks(booking.check_in, booking.check_out).end_track)
  end

  it "projects immutable display-ready financial signals into accessible booking text" do
    booking = StayView::BookingRecord.new(
      booking_room_id: 11,
      booking_id: 7,
      room_type_id: 3,
      room_number: "101",
      status: :confirmed,
      guest_name: "Ada Lovelace",
      check_in: Date.new(2026, 7, 16),
      check_out: Date.new(2026, 7, 18)
    )
    signal = StayView::FinancialSignal.new(
      state: :balance_due,
      label: "Projected balance due · MYR 240.00"
    )

    segment = described_class.call(
      booking:,
      room_type_name: "Deluxe",
      financial_signals: [ signal ],
      date_window: window,
      capabilities: capabilities.with(view_booking: true, view_financial_status: true)
    )

    expect(segment.financial_signals).to eq([ signal ])
    expect(segment.financial_signals).to be_frozen
    expect(segment.accessible_label).to include(signal.label)
  end

  it "discards supplied financial signals when capability is absent" do
    booking = StayView::BookingRecord.new(
      booking_room_id: 11,
      booking_id: 7,
      room_type_id: 3,
      room_number: "101",
      status: :confirmed,
      guest_name: "Ada Lovelace",
      check_in: Date.new(2026, 7, 16),
      check_out: Date.new(2026, 7, 18)
    )
    signal = StayView::FinancialSignal.new(
      state: :balance_due,
      label: "Projected balance due · MYR 240.00"
    )

    segment = described_class.call(
      booking:,
      room_type_name: "Deluxe",
      financial_signals: [ signal ],
      date_window: window,
      capabilities:
    )

    expect(segment.financial_signals).to be_empty
    expect(segment.accessible_label).not_to include("MYR 240.00")
  end
end
