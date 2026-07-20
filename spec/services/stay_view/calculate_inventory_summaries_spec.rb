# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::CalculateInventorySummaries do
  let(:date) { Date.new(2026, 7, 16) }
  let(:capabilities) { StayView::Capabilities.new(**StayView::Capabilities.members.index_with { false }) }

  it "calculates immutable summaries from visible rooms without SQL" do
    group = room_group([
      room("101", occupancies: [ occupancy(:arrival) ]),
      room("102"),
      room("103")
    ])
    inventory = inventory_record(quantity: 2)
    queries = []

    result = ActiveSupport::Notifications.subscribed(
      ->(_name, _start, _finish, _id, payload) { queries << payload[:sql] unless payload[:cached] },
      "sql.active_record"
    ) do
      described_class.call(room_groups: [ group ], room_inventories: [ inventory ], dates: [ date ])
    end

    summary = result.sole.inventory_summary_for(date)
    expect(summary).to have_attributes(date:, sellable: 3, sold: 1, available: 2)
    expect(summary.occupancy).to eq(1.0 / 3)
    expect(queries).to be_empty
    expect(result).to be_frozen
    expect(result.sole.inventory_summaries).to be_frozen
    expect(summary).to be_frozen
  end

  it "treats checkout-only rooms as available and same-day arrivals as sold" do
    checkout_only = room("101", occupancies: [ occupancy(:departure) ])
    turnaround = room("102", occupancies: [ occupancy(:departure), occupancy(:arrival) ])

    summary = calculate([ checkout_only, turnaround ], inventory: inventory_record(quantity: 1))

    expect(summary).to have_attributes(sellable: 2, sold: 1, available: 1, occupancy: 0.5)
  end

  it "subtracts active room blocks from sellable capacity" do
    blocked = room("101", blocks: [ block(start_date: date, end_date: date + 2.days) ])
    outside = room("102", blocks: [ block(start_date: date + 1.day, end_date: date + 2.days) ])

    summary = calculate([ blocked, outside ], inventory: nil)

    expect(summary).to have_attributes(sellable: 1, sold: 0, available: 1, occupancy: 0.0)
  end

  it "uses open quantity and named room inventory as availability caps" do
    rooms = [ room("101"), room("102"), room("103") ]
    quantity_summary = calculate(rooms, inventory: inventory_record(quantity: 1))
    named_summary = calculate(
      rooms,
      inventory: inventory_record(quantity: 3, available_room_numbers: [ "102" ])
    )

    expect(quantity_summary).to have_attributes(sellable: 1, sold: 0, available: 1)
    expect(named_summary).to have_attributes(sellable: 1, sold: 0, available: 1)
  end

  it "falls back to visible rooms when inventory is missing and closes availability when inventory is closed" do
    rooms = [ room("101"), room("102") ]
    missing_summary = calculate(rooms, inventory: nil)
    closed_summary = calculate(rooms, inventory: inventory_record(quantity: 2, status: :closed))

    expect(missing_summary).to have_attributes(sellable: 2, sold: 0, available: 2, occupancy: 0.0)
    expect(closed_summary).to have_attributes(sellable: 0, sold: 0, available: 0, occupancy: nil)
  end

  it "returns unavailable occupancy when every room is blocked" do
    summary = calculate(
      [ room("101", blocks: [ block(start_date: date, end_date: date + 1.day) ]) ],
      inventory: inventory_record(quantity: 0)
    )

    expect(summary).to have_attributes(sellable: 0, sold: 0, available: 0, occupancy: nil)
  end

  it "preserves conflicting sold rooms and exposes occupancy above one hundred percent" do
    summary = calculate(
      [
        room("101", occupancies: [ occupancy(:occupied) ], blocks: [ block(start_date: date, end_date: date + 1.day) ]),
        room("102", occupancies: [ occupancy(:arrival) ])
      ],
      inventory: inventory_record(quantity: 0)
    )

    expect(summary).to have_attributes(sellable: 1, sold: 2, available: 0, occupancy: 2.0)
  end

  private

  def calculate(rooms, inventory:)
    described_class.call(
      room_groups: [ room_group(rooms) ],
      room_inventories: Array(inventory),
      dates: [ date ]
    ).sole.inventory_summary_for(date)
  end

  def room_group(rooms)
    StayView::RoomGroup.new(room_type_id: 3, name: "Deluxe", rooms:)
  end

  def room(number, occupancies: [], blocks: [])
    occupancies = [ occupancy(:available) ] if occupancies.empty?
    StayView::RoomRow.new(
      key: "3:#{number}",
      dom_id: "room-#{number}",
      room_number: number,
      room_type_id: 3,
      room_type_name: "Deluxe",
      smoking_allowed: false,
      pets_allowed: false,
      current_physical_status: :ready,
      operational_flags: {},
      day_cells: [ StayView::DayCell.new(date:, occupancies:) ],
      booking_segments: [],
      operational_segments: blocks,
      capabilities:
    )
  end

  def occupancy(state)
    StayView::Occupancy.new(state:, label: state.to_s.humanize)
  end

  def block(start_date:, end_date:)
    StayView::OperationalSegment.new(
      dom_id: "block-#{start_date}",
      room_block_id: 1,
      kind: :maintenance,
      label: "Maintenance",
      start_date:,
      end_date:,
      start_track: 1,
      end_track: 3,
      clipped_left: false,
      clipped_right: false,
      accessible_label: "Maintenance",
      capabilities:
    )
  end

  def inventory_record(quantity:, status: :open, available_room_numbers: [])
    StayView::RoomInventoryRecord.new(
      room_type_id: 3,
      date:,
      quantity:,
      status:,
      available_room_numbers:
    )
  end
end
