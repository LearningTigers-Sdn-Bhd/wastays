# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::ProjectRoom do
  let(:window) do
    hotel = create(:hotel, accounting_business_date: Date.new(2026, 7, 16))
    StayView::DateWindow.new(hotel:, start_date: "2026-07-16", days: 7)
  end

  let(:capabilities) do
    StayView::Capabilities.new(
      **StayView::Capabilities.members.index_with { false }.merge(view_board: true, view_booking: true)
    )
  end

  it "projects inclusive room blocks as full-day half-open segments without SQL" do
    room_type = StayView::RoomTypeRecord.new(
      id: 3,
      name: "Deluxe",
      room_numbers: [ "101" ],
      smoking_allowed: false,
      pets_allowed: false
    )
    block = StayView::RoomBlockRecord.new(
      id: 4,
      room_type_id: 3,
      room_number: "101",
      block_type: :maintenance,
      reason: "Repairs",
      start_date: Date.new(2026, 7, 17),
      end_date: Date.new(2026, 7, 18)
    )
    sql = []
    subscriber = lambda { |_name, _start, _finish, _id, payload| sql << payload[:sql] unless payload[:cached] }
    current_window = window

    row = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      described_class.call(
        room_type:,
        room_number: "101",
        bookings: [],
        room_status: nil,
        room_blocks: [ block ],
        date_window: current_window,
        capabilities:
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


  it "projects immutable housekeeping alerts without executing SQL" do
    room_type = StayView::RoomTypeRecord.new(
      id: 3,
      name: "Deluxe",
      room_numbers: [ "101" ],
      smoking_allowed: false,
      pets_allowed: false
    )
    alert = StayView::HousekeepingAlertRecord.new(
      request_id: 9,
      room_type_id: 3,
      room_number: "101",
      details: "Fresh towels",
      status: :assigned,
      requested_at: Time.zone.local(2026, 7, 16, 9),
      assigned_to_id: 4,
      assigned_to_name: "Sam"
    )
    sql = []
    current_window = window

    row = ActiveSupport::Notifications.subscribed(
      ->(_name, _start, _finish, _id, payload) { sql << payload[:sql] unless payload[:cached] },
      "sql.active_record"
    ) do
      described_class.call(
        room_type:,
        room_number: "101",
        bookings: [],
        room_status: nil,
        room_blocks: [],
        housekeeping_alerts: [ alert ],
        date_window: current_window,
        capabilities:
      )
    end

    expect(sql).to be_empty
    expect(row.housekeeping_alerts.sole).to have_attributes(
      room_key: "3:101",
      details: "Fresh towels",
      status: :assigned,
      assigned_to_name: "Sam"
    )
    expect(row.housekeeping_alerts).to be_frozen
  end
end
