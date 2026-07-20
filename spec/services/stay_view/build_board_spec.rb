# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::BuildBoard do
  let(:start_date) { Date.new(2026, 7, 16) }
  let(:hotel) { create(:hotel, accounting_business_date: start_date) }
  let(:user) { create(:user, account: hotel.account) }
  let(:role) { create(:role, account: hotel.account) }

  before do
    permission = Permission.find_or_create_by!(slug: "view_bookings") { |record| record.name = "View Bookings" }
    create(:role_permission, role:, permission:)
    create(:user_hotel_access, user:, hotel:, role:)
  end

  it "builds immutable scalar view models for sequential, completed, and grouped one-room stays" do
    deluxe = create(:room_type, hotel:, name: "Deluxe", room_numbers: %w[101 102])
    suite = create(:room_type, hotel:, name: "Suite", room_numbers: [ "201" ])
    first = create(:booking, hotel:, check_in: start_date, check_out: start_date + 1.day, guest_name: "First Guest")
    completed = create(:booking, hotel:, status: "completed", check_in: start_date - 2.days, check_out: start_date + 1.day, guest_name: "Past Guest")
    group = create(:group_booking, hotel:, name: "Tour Group")
    grouped_deluxe = create(
      :booking, hotel:, group_booking: group, group_position: 1,
      check_in: start_date + 1.day, check_out: start_date + 3.days, guest_name: "First Group Guest"
    )
    grouped_suite = create(
      :booking, hotel:, group_booking: group, group_position: 2,
      check_in: start_date + 1.day, check_out: start_date + 3.days, guest_name: "Second Group Guest"
    )
    create(:booking_room, booking: first, room_type: deluxe, room_number: "101")
    create(:booking_room, booking: completed, room_type: deluxe, room_number: "102")
    create(:booking_room, booking: grouped_deluxe, room_type: deluxe, room_number: "101")
    create(:booking_room, booking: grouped_suite, room_type: suite, room_number: "201")

    board = described_class.call(hotel:, user:, start_date:, days: 7)
    rows = board.room_groups.flat_map(&:rooms)

    expect(rows.size).to eq(3)
    expect(rows.find { |row| row.room_number == "101" }.occupancy_for(start_date + 1.day).map(&:state)).to contain_exactly(:departure, :arrival)
    expect(rows.find { |row| row.room_number == "102" }.booking_segments.map(&:status)).to eq([ :completed ])
    grouped_segments = rows.flat_map(&:booking_segments).select { |segment| segment.group_booking_id == group.id }
    expect(grouped_segments.map(&:booking_id)).to contain_exactly(grouped_deluxe.id, grouped_suite.id)
    expect(grouped_segments.map(&:booking_room_id)).to contain_exactly(
      grouped_deluxe.booking_rooms.sole.id,
      grouped_suite.booking_rooms.sole.id
    )
    expect(grouped_segments.map(&:group_reference).uniq).to eq([ group.formatted_reservation_number ])
    expect(grouped_segments.map(&:group_name).uniq).to eq([ "Tour Group" ])
    expect(grouped_segments.map(&:group_position)).to contain_exactly(1, 2)
    expect(board).to be_frozen
    expect(board.room_groups).to be_frozen
    expect(rows.first.day_cells).to be_frozen
    expect(active_record_values(board)).to be_empty
  end

  it "excludes non-occupying booking statuses" do
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    %w[cancelled no_show pending overbooked].each do |status|
      booking = create(:booking, hotel:, status:, check_in: start_date, check_out: start_date + 2.days)
      create(:booking_room, booking:, room_type:, room_number: "101")
    end

    row = described_class.call(hotel:, user:, start_date:, days: 7).room_groups.first.rooms.first

    expect(row.booking_segments).to be_empty
    expect(row.occupancy_for(start_date).map(&:state)).to eq([ :available ])
  end

  it "applies filters before calculating counts" do
    deluxe = create(:room_type, hotel:, name: "Deluxe", room_numbers: [ "101" ])
    suite = create(:room_type, hotel:, name: "Suite", room_numbers: [ "201" ])
    create(:room_status, hotel:, room_type: deluxe, room_number: "101", status: "dirty")
    create(:room_status, hotel:, room_type: suite, room_number: "201", status: "ready")
    booking = create(:booking, hotel:, check_in: start_date, check_out: start_date + 2.days)
    create(:booking_room, booking:, room_type: deluxe, room_number: "101")

    board = described_class.call(
      hotel:, user:, start_date:, days: 7,
      filters: { room_type_id: deluxe.id, occupancy: "arrival", physical_status: "dirty" }
    )

    expect(board.room_groups.map(&:room_type_id)).to eq([ deluxe.id ])
    expect(board.status_counts.reference_date).to eq(start_date)
      expect(board.status_counts.room_states).to eq(
        all: 1, vacant: 0, arrival: 1, occupied: 0, departure: 0, turnover: 0, blocked: 0, dirty: 1
      )
      expect(board.room_card_presentation_for(board.room_groups.first.rooms.first).state).to eq(:arrival)
    expect(board.room_groups.sole.inventory_summary_for(start_date)).to have_attributes(
      sellable: 1,
      sold: 1,
      available: 0,
      occupancy: 1.0
    )
  end

  it "builds date summaries from authoritative inventory without exposing active records" do
    room_type = create(:room_type, hotel:, room_numbers: %w[101 102])
    booking = create(:booking, hotel:, check_in: start_date, check_out: start_date + 1.day)
    create(:booking_room, booking:, room_type:, room_number: "101")
    create(:room_inventory, room_type:, date: start_date, quantity: 1, available_room_numbers: [ "102" ])

    board = described_class.call(hotel:, user:, start_date:, days: 7)
    group = board.room_groups.sole

    expect(group.inventory_summaries.size).to eq(7)
    expect(group.inventory_summary_for(start_date)).to have_attributes(
      sellable: 2,
      sold: 1,
      available: 1,
      occupancy: 0.5
    )
    expect(group.inventory_summary_for(start_date + 1.day)).to have_attributes(
      sellable: 2,
      sold: 0,
      available: 2,
      occupancy: 0.0
    )
    expect(board.footer_summaries.size).to eq(7)
    expect(board.footer_summaries.first).to have_attributes(
      date: start_date,
      sellable: 2,
      sold: 1,
      available: 1,
      occupancy: 0.5
    )
    expect(board.footer_summaries).to be_frozen
    expect(active_record_values(board)).to be_empty
  end

  it "ignores the removed booking status filter instead of altering occupancy" do
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    booking = create(:booking, hotel:, check_in: start_date, check_out: start_date + 2.days)
    create(:booking_room, booking:, room_type:, room_number: "101")

    board = described_class.call(hotel:, user:, start_date:, days: 7, filters: { booking_status: "cancelled" })

    expect(board.filters.to_h).not_to have_key(:booking_status)
    expect(board.status_counts.all).to eq(1)
    expect(board.room_groups.first.rooms.first.booking_segments.map(&:status)).to eq([ :confirmed ])
  end

  it "filters linked room types and recalculates summaries for an explicit rate plan" do
    manage_rates = Permission.find_or_create_by!(slug: "manage_rates") { |record| record.name = "Manage Rates" }
    create(:role_permission, role:, permission: manage_rates)
    deluxe = create(:room_type, hotel:, name: "Deluxe", room_numbers: [ "101" ], base_price: 100)
    suite = create(:room_type, hotel:, name: "Suite", room_numbers: [ "201" ], base_price: 200)
    flexible = create(:rate_plan, hotel:, name: "Flexible", currency: "USD")
    create(:room_type_rate_plan, room_type: deluxe, rate_plan: flexible)
    create(:room_rate, room_type: deluxe, rate_plan: flexible, date: start_date, price: 175, currency: "USD")

    board = described_class.call(
      hotel:, user:, start_date:, days: 7,
      filters: { rate_plan_id: flexible.id, room_type_id: suite.id }
    )

    expect(board.filters.rate_plan_id).to eq(flexible.id)
    expect(board.filters.room_type_id).to be_nil
    expect(board.room_type_options.map(&:id)).to eq([ deluxe.id ])
    expect(board.room_groups.map(&:room_type_id)).to eq([ deluxe.id ])
    expect(board.status_counts.all).to eq(1)
    expect(board.room_groups.sole.inventory_summary_for(start_date).standard_rate).to have_attributes(
      amount: 175.to_d,
      currency: "USD"
    )
    expect(board.room_groups.sole.inventory_summary_for(start_date + 1.day).standard_rate).to be_nil
  end

  it "canonicalizes an unavailable rate plan to Standard" do
    manage_rates = Permission.find_or_create_by!(slug: "manage_rates") { |record| record.name = "Manage Rates" }
    create(:role_permission, role:, permission: manage_rates)
    create(:room_type, hotel:, name: "Deluxe", room_numbers: [ "101" ])
    foreign_plan = create(:rate_plan, hotel: create(:hotel), name: "Foreign")

    board = described_class.call(
      hotel:, user:, start_date:, days: 7, filters: { rate_plan_id: foreign_plan.id }
    )

    expect(board.filters.rate_plan_id).to be_nil
    expect(board.room_groups.size).to eq(1)
    expect(board.rate_plan_options.map(&:id)).not_to include(foreign_plan.id)
  end

  it "redacts guest names before inventory leaves the loader" do
    readiness = Permission.find_or_create_by!(slug: "view_room_readiness") { |record| record.name = "View Room Readiness" }
    role.role_permissions.delete_all
    create(:role_permission, role:, permission: readiness)
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    booking = create(:booking, hotel:, check_in: start_date, check_out: start_date + 2.days, guest_name: "Sensitive Name")
    create(:booking_room, booking:, room_type:, room_number: "101")

    board = described_class.call(hotel:, user:, start_date:, days: 7)
    segment = board.room_groups.first.rooms.first.booking_segments.first

    expect(segment.guest_label).to eq("Reserved")
    expect(segment.accessible_label).not_to include("Sensitive Name")
  end

  it "publishes build metrics" do
    create(:room_type, hotel:, room_numbers: [ "101" ])
    events = []

    ActiveSupport::Notifications.subscribed(->(*args) { events << ActiveSupport::Notifications::Event.new(*args) }, described_class::EVENT_NAME) do
      described_class.call(hotel:, user:, start_date:, days: 7)
    end

    expect(events.one?).to be(true)
    expect(events.first.payload).to include(:duration_ms, row_count: 1, segment_count: 0, operational_segment_count: 0)
  end

  it "keeps query count stable as projected rows, dates, and inventory records grow" do
    small_hotel, small_user = create_board_fixture(room_count: 1, days: 7)
    large_hotel, large_user = create_board_fixture(room_count: 6, days: 30)

    small_count = count_sql_queries { described_class.call(hotel: small_hotel, user: small_user, start_date:, days: 7) }
    large_count = count_sql_queries { described_class.call(hotel: large_hotel, user: large_user, start_date:, days: 30) }

    expect(large_count).to be <= small_count + 1
  end

  def create_board_fixture(room_count:, days:)
    current_hotel = create(:hotel, accounting_business_date: start_date)
    current_user = create(:user, account: current_hotel.account)
    current_role = create(:role, account: current_hotel.account)
    permission = Permission.find_or_create_by!(slug: "view_bookings") { |record| record.name = "View Bookings" }
    create(:role_permission, role: current_role, permission:)
    create(:user_hotel_access, user: current_user, hotel: current_hotel, role: current_role)
    room_numbers = room_count.times.map { |index| (200 + index).to_s }
    room_type = create(:room_type, hotel: current_hotel, room_numbers: room_numbers)
    days.times do |offset|
      create(:room_inventory, room_type:, date: start_date + offset.days, quantity: room_count)
    end

    room_numbers.each do |room_number|
      create(:room_status, hotel: current_hotel, room_type:, room_number:, status: "dirty")
      create(
        :housekeeping_request,
        booking: nil,
        hotel: current_hotel,
        room_type:,
        room_number:,
        status: "new",
        request_details: "Clean room #{room_number}"
      )
      booking = create(:booking, hotel: current_hotel, check_in: start_date, check_out: start_date + 2.days)
      create(:booking_room, booking:, room_type:, room_number:)
    end

    [ current_hotel, current_user ]
  end

  def count_sql_queries
    queries = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      next if payload[:cached]
      next if %w[SCHEMA TRANSACTION].include?(payload[:name])

      queries << payload[:sql]
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries.count
  end

  def active_record_values(value, found = [])
    case value
    when ActiveRecord::Base
      found << value
    when Data
      value.to_h.each_value { |item| active_record_values(item, found) }
    when Array
      value.each { |item| active_record_values(item, found) }
    when Hash
      value.each_value { |item| active_record_values(item, found) }
    end
    found
  end
end
