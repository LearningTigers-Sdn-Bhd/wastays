# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::LoadInventory do
  let(:start_date) { Date.new(2026, 7, 16) }
  let(:hotel) { create(:hotel, accounting_business_date: start_date) }
  let(:window) { StayView::DateWindow.new(hotel:, start_date:, days: 7) }
  let(:capabilities) do
    StayView::Capabilities.new(
      **StayView::Capabilities.members.index_with { false }.merge(view_board: true, view_room_readiness: true)
    )
  end

  it "loads bounded scalar inventory and redacts booking identity without permission" do
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    create(:room_status, hotel:, room_type:, room_number: "101", status: "dirty")
    booking = create(
      :booking,
      hotel:,
      group_booking: create(:group_booking, hotel:, name: "Sensitive Group"),
      group_position: 1,
      check_in: start_date,
      check_out: start_date + 2.days,
      guest_name: "Sensitive Name"
    )
    create(:booking_room, booking:, room_type:, room_number: "101")
    create(
      :room_block,
      hotel:,
      room_type:,
      room_number: "101",
      start_date:,
      end_date: start_date + 1.day
    )

    inventory = described_class.call(hotel:, date_window: window, capabilities:)

    expect(inventory.room_types.map(&:id)).to eq([ room_type.id ])
    expect(inventory.bookings.map(&:guest_name)).to eq([ nil ])
    expect(inventory.bookings.first).to have_attributes(
      group_booking_id: booking.group_booking_id,
      group_reference: nil,
      group_name: nil,
      group_position: 1
    )
    expect(inventory.room_statuses.map(&:status)).to eq([ :dirty ])
    expect(inventory.room_blocks.size).to eq(1)
    expect(inventory).to be_frozen
    expect(inventory.bookings).to be_frozen
  end

  it "loads display-ready group identity as scalar values with booking permission" do
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    group = create(:group_booking, hotel:, name: "Conference Group")
    booking = create(
      :booking,
      hotel:,
      group_booking: group,
      group_position: 2,
      check_in: start_date,
      check_out: start_date + 2.days
    )
    create(:booking_room, booking:, room_type:, room_number: "101")
    visible_capabilities = capabilities.with(view_booking: true)

    record = described_class.call(hotel:, date_window: window, capabilities: visible_capabilities).bookings.first

    expect(record).to have_attributes(
      group_booking_id: group.id,
      group_reference: group.formatted_reservation_number,
      group_name: "Conference Group",
      group_position: 2
    )
    expect(record.group_reference).to be_frozen
    expect(record.group_name).to be_frozen
  end

  it "loads active hotel-owned and legacy booking-owned housekeeping alerts without booking identity" do
    room_type = create(:room_type, hotel:, room_numbers: %w[101 102])
    booking = create(:booking, hotel:, guest_name: "Sensitive Guest", check_in: start_date, check_out: start_date + 2.days)
    create(:booking_room, booking:, room_type:, room_number: "102")
    direct = create(
      :housekeeping_request,
      booking: nil,
      hotel:,
      room_type:,
      room_number: "101",
      request_details: "Replace towels",
      status: "assigned",
      metadata: { "assigned_to" => 7, "assigned_to_name" => "Sam" }
    )
    legacy = create(
      :housekeeping_request,
      booking:,
      hotel: nil,
      room_type: nil,
      room_number: nil,
      request_details: "Bring water",
      status: "in_progress"
    )
    create(:housekeeping_request, booking:, status: "completed", request_details: "Excluded completed")
    create(:housekeeping_request, booking:, status: "new", archived_at: Time.current, request_details: "Excluded archived")
    create(:housekeeping_request, booking:, status: "pending", request_details: "Excluded pending")

    alerts = described_class.call(hotel:, date_window: window, capabilities:).housekeeping_alerts

    expect(alerts.map(&:request_id)).to contain_exactly(direct.id, legacy.id)
    expect(alerts.find { |alert| alert.request_id == direct.id }).to have_attributes(
      room_type_id: room_type.id,
      room_number: "101",
      details: "Replace towels",
      status: :assigned,
      assigned_to_id: 7,
      assigned_to_name: "Sam"
    )
    expect(alerts.find { |alert| alert.request_id == legacy.id }).to have_attributes(
      room_type_id: room_type.id,
      room_number: "102",
      details: "Bring water",
      status: :in_progress
    )
    expect(StayView::HousekeepingAlertRecord.members).not_to include(:booking_id, :guest_name)
    expect(alerts).to be_frozen
  end

  it "loads the primary guest and every occupying group room in one display-ready collection" do
    room_type = create(:room_type, hotel:, name: "Deluxe", room_numbers: %w[101 102 103])
    group = create(:group_booking, hotel:, name: "Conference Group")
    visible = create(:booking, hotel:, group_booking: group, group_position: 1, check_in: start_date, check_out: start_date + 2.days)
    outside = create(:booking, hotel:, group_booking: group, group_position: 2, status: "completed", check_in: start_date - 30.days, check_out: start_date - 29.days)
    cancelled = create(:booking, hotel:, group_booking: group, group_position: 3, status: "cancelled", check_in: start_date, check_out: start_date + 2.days)
    create(:booking_room, booking: visible, room_type:, room_number: "101")
    create(:booking_room, booking: outside, room_type:, room_number: "102")
    create(:booking_room, booking: cancelled, room_type:, room_number: "103")
    primary_guest = create(:guest, name: "Primary Snapshot Guest")
    create(:booking_guest, booking: visible, guest: primary_guest, is_primary: true, role: "primary")

    inventory = described_class.call(hotel:, date_window: window, capabilities: capabilities.with(view_booking: true))

    expect(inventory.bookings.sole.primary_guest_name).to eq("Primary Snapshot Guest")
    expect(inventory.group_rooms.fetch(group.id).map(&:booking_id)).to eq([ visible.id, outside.id ])
    expect(inventory.group_rooms.fetch(group.id).map(&:room_number)).to eq(%w[101 102])
    expect(inventory.group_rooms).to be_frozen
    expect(inventory.group_rooms.fetch(group.id)).to be_frozen
  end
end
