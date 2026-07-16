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
      filters: { room_type_id: deluxe.id, booking_status: "confirmed", occupancy: "arrival", physical_status: "dirty" }
    )

    expect(board.room_groups.map(&:room_type_id)).to eq([ deluxe.id ])
    expect(board.status_counts.rooms).to eq(1)
    expect(board.status_counts.physical_statuses).to eq(dirty: 1)
    expect(board.status_counts.booking_statuses).to eq(confirmed: 1)
    expect(board.status_counts.occupancies[:arrival]).to eq(1)
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
    expect(active_record_values(board)).to be_empty
  end

  it "ignores a non-occupying booking status filter instead of emptying the board" do
    room_type = create(:room_type, hotel:, room_numbers: [ "101" ])
    booking = create(:booking, hotel:, check_in: start_date, check_out: start_date + 2.days)
    create(:booking_room, booking:, room_type:, room_number: "101")

    board = described_class.call(hotel:, user:, start_date:, days: 7, filters: { booking_status: "cancelled" })

    expect(board.filters.booking_status).to be_nil
    expect(board.status_counts.rooms).to eq(1)
    expect(board.room_groups.first.rooms.first.booking_segments.map(&:status)).to eq([ :confirmed ])
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
