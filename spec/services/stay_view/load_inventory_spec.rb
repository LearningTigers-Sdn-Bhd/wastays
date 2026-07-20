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

  it "does not select pricing scalars or query pricing tables without rate permission" do
    create(:room_type, hotel:, room_numbers: [ "101" ], base_price: 987.65)
    sql = capture_sql do
      @inventory = described_class.call(hotel:, date_window: window, capabilities:, rate_plan_id: 999)
    end

    expect(@inventory.room_types.sole).to have_attributes(
      base_price: nil, master_rate_plan_id: nil, rate_currency: nil
    )
    expect(@inventory.standard_rates).to be_empty
    expect(@inventory.rate_plan_options).to be_empty
    expect(@inventory.selected_rate_plan_id).to be_nil
    expect(sql.join(" ")).not_to include("room_type_rate_plans", "room_rates", "base_price")
  end

  it "loads scoped immutable standard-rate records in a bounded pricing query set" do
    visible = capabilities.with(view_rates: true)
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ], base_price: 100)
    master_plan = room_type.rate_plans.order(:id).first
    included = create(:room_rate, room_type:, rate_plan: master_plan, date: start_date, price: 145, currency: master_plan.currency)
    create(:room_rate, room_type:, rate_plan: nil, date: start_date + 1.day, price: 120, currency: master_plan.currency)
    create(:room_rate, room_type:, rate_plan: master_plan, date: window.end_date, price: 999, currency: master_plan.currency)
    other_room_type = create(:room_type, hotel: create(:hotel), base_price: 500)
    create(:room_rate, room_type: other_room_type, rate_plan: other_room_type.rate_plans.first, date: start_date, price: 777)

    sql = capture_sql { @inventory = described_class.call(hotel:, date_window: window, capabilities: visible) }
    pricing_queries = sql.grep(/(?:room_type_rate_plans|FROM "room_rates")/)

    expect(@inventory.room_types.sole).to have_attributes(
      base_price: 100.to_d, master_rate_plan_id: master_plan.id, rate_currency: master_plan.currency
    )
    expect(@inventory.standard_rates.map(&:price)).to contain_exactly(145.to_d, 120.to_d)
    expect(@inventory.standard_rates.map(&:room_type_id).uniq).to eq([ room_type.id ])
    expect(@inventory.standard_rates.find { |record| record.price == 145 }).to have_attributes(
      date: start_date, rate_plan_id: master_plan.id, currency: included.currency
    )
    expect(@inventory.standard_rates).to be_frozen
    expect(@inventory.rate_plan_options.sole).to have_attributes(
      id: master_plan.id,
      label: "#{master_plan.name} — #{room_type.name}",
      room_type_ids: [ room_type.id ]
    )
    expect(pricing_queries.size).to eq(2)
  end

  it "loads only an explicitly selected hotel plan and its linked room types" do
    visible = capabilities.with(view_rates: true)
    deluxe = create(:room_type, hotel:, name: "Deluxe", room_numbers: [ "101" ], base_price: 100)
    suite = create(:room_type, hotel:, name: "Suite", room_numbers: [ "201" ], base_price: 200)
    flexible = create(:rate_plan, hotel:, name: "Flexible", currency: "USD")
    create(:room_type_rate_plan, room_type: deluxe, rate_plan: flexible)
    selected_rate = create(:room_rate, room_type: deluxe, rate_plan: flexible, date: start_date, price: 175, currency: "USD")
    create(:room_rate, room_type: suite, rate_plan: suite.rate_plans.first, date: start_date, price: 999)

    sql = capture_sql do
      @inventory = described_class.call(
        hotel:, date_window: window, capabilities: visible, rate_plan_id: flexible.id
      )
    end
    inventory = @inventory

    expect(inventory.selected_rate_plan_id).to eq(flexible.id)
    expect(inventory.standard_rates).to contain_exactly(
      have_attributes(
        room_type_id: deluxe.id,
        rate_plan_id: flexible.id,
        price: selected_rate.price,
        currency: "USD"
      )
    )
    expect(inventory.rate_plan_options.find { |option| option.id == flexible.id }).to have_attributes(
      room_type_ids: [ deluxe.id ],
      label: "Flexible — Deluxe"
    )
    expect(inventory.rate_plan_options).to be_frozen
    expect(sql.grep(/(?:room_type_rate_plans|FROM "room_rates")/).size).to eq(2)
  end

  it "falls back to Standard for a cross-hotel rate plan" do
    visible = capabilities.with(view_rates: true)
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ], base_price: 100)
    master_plan = room_type.rate_plans.first
    create(:room_rate, room_type:, rate_plan: master_plan, date: start_date, price: 145, currency: master_plan.currency)
    foreign_plan = create(:rate_plan, hotel: create(:hotel), name: "Foreign")

    inventory = described_class.call(
      hotel:, date_window: window, capabilities: visible, rate_plan_id: foreign_plan.id
    )

    expect(inventory.selected_rate_plan_id).to be_nil
    expect(inventory.rate_plan_options.map(&:id)).not_to include(foreign_plan.id)
    expect(inventory.standard_rates.sole.rate_plan_id).to eq(master_plan.id)
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

  it "loads late checkouts into both the Room and Timeline views by actual occupancy" do
    business_date = Date.new(2026, 7, 19)
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    zone = hotel.hotel_time_zone
    booking = create(
      :booking,
      hotel:,
      status: "completed",
      check_in: zone.local(2026, 7, 17, 15),
      check_out: zone.local(2026, 7, 18, 12),
      checked_in_at: zone.local(2026, 7, 17, 15),
      checked_out_at: zone.local(2026, 7, 19, 8)
    )
    create(:booking_room, booking:, room_type:, room_number: "101")
    room_window = StayView::DateWindow.new(hotel:, start_date: business_date, view_mode: :rooms)
    timeline_window = StayView::DateWindow.new(hotel:, start_date: business_date, days: 7, view_mode: :timeline)

    room_inventory = described_class.call(hotel:, date_window: room_window, capabilities:)
    timeline_inventory = described_class.call(hotel:, date_window: timeline_window, capabilities:)

    expected_attributes = {
      check_in: Date.new(2026, 7, 17),
      check_out: Date.new(2026, 7, 18),
      check_in_at: zone.local(2026, 7, 17, 15),
      check_out_at: zone.local(2026, 7, 18, 12),
      actual_check_in: Date.new(2026, 7, 17),
      actual_check_out: Date.new(2026, 7, 19),
      actual_check_in_at: zone.local(2026, 7, 17, 15),
      actual_check_out_at: zone.local(2026, 7, 19, 8)
    }
    expect(room_inventory.bookings.sole).to have_attributes(expected_attributes)
    # The scheduled checkout (18 Jul) falls before the 19 Jul timeline window,
    # but the actual checkout (19 Jul) keeps the stay in view so the turnover
    # renders instead of silently disappearing.
    expect(timeline_inventory.bookings.sole).to have_attributes(expected_attributes)
  end

  it "loads room-status notes only with readiness permission without adding queries" do
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    create(
      :room_status,
      hotel:,
      room_type:,
      room_number: "101",
      status: "inspection_failed",
      notes: "Dust on headboard",
      priority: true,
      priority_note: "Prepare before noon"
    )

    visible_sql = capture_sql { @visible = described_class.call(hotel:, date_window: window, capabilities:) }
    hidden_sql = capture_sql do
      @hidden = described_class.call(
        hotel:,
        date_window: window,
        capabilities: capabilities.with(view_room_readiness: false)
      )
    end

    expect(@visible.room_statuses.sole).to have_attributes(
      status_note: "Dust on headboard",
      priority_note: "Prepare before noon"
    )
    expect(@hidden.room_statuses.sole).to have_attributes(status_note: nil, priority_note: nil)
    expect(visible_sql.count { |sql| sql.include?('FROM "room_statuses"') }).to eq(1)
    expect(hidden_sql.count { |sql| sql.include?('FROM "room_statuses"') }).to eq(1)
    expect(hidden_sql.join(" ")).not_to include('"room_statuses"."notes"', '"room_statuses"."priority_note"')
  end

  def capture_sql
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])

      queries << payload[:sql]
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  it "loads immutable room inventory records only for the hotel room types and visible dates" do
    room_type = create(:room_type, hotel:, room_numbers: %w[101 102])
    other_hotel = create(:hotel)
    other_room_type = create(:room_type, hotel: other_hotel, room_numbers: [ "201" ])
    included = create(
      :room_inventory,
      room_type:,
      date: start_date,
      quantity: 1,
      status: "open",
      available_room_numbers: [ "102" ]
    )
    create(:room_inventory, room_type:, date: window.end_date, quantity: 2)
    create(:room_inventory, room_type: other_room_type, date: start_date, quantity: 1)

    records = described_class.call(hotel:, date_window: window, capabilities:).room_inventories

    expect(records.map(&:room_type_id)).to eq([ room_type.id ])
    expect(records.sole).to have_attributes(
      date: start_date,
      quantity: included.quantity,
      status: :open,
      available_room_numbers: [ "102" ]
    )
    expect(records).to be_frozen
    expect(records.sole.available_room_numbers).to be_frozen
  end

  it "excludes completed and out-of-range room blocks before inventory summary projection" do
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    create(
      :room_block,
      hotel:,
      room_type:,
      room_number: "101",
      start_date:,
      end_date: start_date + 1.day,
      completed_at: Time.current
    )
    create(
      :room_block,
      hotel:,
      room_type:,
      room_number: "101",
      start_date: window.end_date,
      end_date: window.end_date + 1.day
    )

    inventory = described_class.call(hotel:, date_window: window, capabilities:)

    expect(inventory.room_blocks).to be_empty
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

  it "loads booking pax and primary-guest boat times as bounded scalars when enabled" do
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    booking = create(
      :booking,
      hotel:,
      adults: 3,
      children: 2,
      check_in: start_date,
      check_out: start_date + 2.days
    )
    create(:booking_room, booking:, room_type:, room_number: "101")
    primary = create(
      :booking_guest,
      booking:,
      is_primary: true,
      boat_in_at: Time.zone.local(2026, 7, 16, 9),
      boat_out_at: Time.zone.local(2026, 7, 18, 7)
    )
    visible = capabilities.with(view_booking: true)

    sql = capture_sql { @inventory = described_class.call(hotel:, date_window: window, capabilities: visible) }

    expect(@inventory.bookings.sole).to have_attributes(
      adults: 3,
      children: 2,
      boat_in_at: primary.boat_in_at,
      boat_out_at: primary.boat_out_at
    )
    booking_queries = sql.grep(/FROM "booking_rooms"/)
    expect(booking_queries.size).to eq(1)
    expect(booking_queries.sole).to include("boat_in_at", "boat_out_at", '"bookings"."adults"', '"bookings"."children"')
  end

  it "does not select pax or boat scalars when booking identity is redacted" do
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    booking = create(:booking, hotel:, adults: 3, children: 2, check_in: start_date, check_out: start_date + 2.days)
    create(:booking_room, booking:, room_type:, room_number: "101")
    create(:booking_guest, booking:, is_primary: true, boat_in_at: Time.zone.local(2026, 7, 16, 9))

    sql = capture_sql { @inventory = described_class.call(hotel:, date_window: window, capabilities:) }

    expect(@inventory.bookings.sole).to have_attributes(adults: nil, children: nil, boat_in_at: nil, boat_out_at: nil)
    booking_query = sql.grep(/FROM "booking_rooms"/).sole
    expect(booking_query).not_to include("boat_in_at", "boat_out_at", '"bookings"."adults"', '"bookings"."children"')
  end

  it "loads active hotel-owned and legacy booking-owned housekeeping alerts without booking identity" do
    room_type = create(:room_type, hotel:, room_numbers: %w[101 102])
    booking = create(:booking, hotel:, guest_name: "Sensitive Guest", check_in: start_date, check_out: start_date + 2.days)
    create(:booking_room, booking:, room_type:, room_number: "102")
    assignment_history = (1..6).map do |number|
      {
        "assigned_to_name" => "Housekeeper #{number}",
        "assigned_by_name" => ("Manager" unless number == 6),
        "timestamp" => Time.zone.local(2026, 7, 16, number).iso8601
      }
    end
    assignment_history << { "assigned_to_name" => "Malformed", "timestamp" => "not-a-time" }
    direct = create(
      :housekeeping_request,
      booking: nil,
      hotel:,
      room_type:,
      room_number: "101",
      request_details: "Replace towels",
      status: "assigned",
      metadata: { "assigned_to" => 7, "assigned_to_name" => "Sam", "assignment_history" => assignment_history }
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
    expect(alerts.find { |alert| alert.request_id == direct.id }.assignment_history.map(&:assigned_to_name)).to eq(
      [ "Housekeeper 6", "Housekeeper 5", "Housekeeper 4", "Housekeeper 3", "Housekeeper 2" ]
    )
    expect(alerts.find { |alert| alert.request_id == direct.id }.assignment_history.first.assigned_by_name).to eq("System")
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
