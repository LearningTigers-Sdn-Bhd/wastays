# frozen_string_literal: true

require "rails_helper"

RSpec.describe StayView::BoardState do
  let(:hotel) { create(:hotel, accounting_business_date: Date.new(2026, 7, 16)) }

  it "normalizes timeline URL state and filters" do
    state = described_class.new(hotel:, params: {
      view: "timeline",
      start_date: "2026-07-20",
      days: "21",
      density: "comfortable",
      occupancy: "arrival",
      rate_plan_id: "42",
      booking_status: "confirmed"
    })

    expect(state).to have_attributes(view_mode: :timeline, density: :compact)
    expect(state.date_window).to have_attributes(start_date: Date.new(2026, 7, 20), days: 21)
    expect(state.filters).to have_attributes(occupancy: :arrival, rate_plan_id: 42)
    expect(state.query).to include(
      view: :timeline, start_date: Date.new(2026, 7, 20), days: 21, occupancy: :arrival, rate_plan_id: 42
    )
    expect(state.query).not_to have_key(:density)
    expect(state.query).not_to have_key(:booking_status)
  end

  it "tracks room grouping as URL state, defaulting to room type" do
    default = described_class.new(hotel:, params: { view: "rooms", date: "2026-07-16" })
    expect(default).to have_attributes(room_grouping: "room_type", grouped_rooms?: true)
    expect(default.query).not_to have_key(:group_by)

    ungrouped = described_class.new(hotel:, params: { view: "rooms", date: "2026-07-16", group_by: "none" })
    expect(ungrouped).to have_attributes(room_grouping: "none", grouped_rooms?: false)
    expect(ungrouped.query).to include(view: :rooms, group_by: "none")

    invalid = described_class.new(hotel:, params: { view: "rooms", date: "2026-07-16", group_by: "sideways" })
    expect(invalid.room_grouping).to eq("room_type")
  end

  it "keeps the six-state filter only in Room View" do
    room_state = described_class.new(hotel:, params: {
      view: "rooms",
      date: "2026-07-16",
      room_state: "turnover",
      occupancy: "arrival"
    })
    timeline = described_class.new(hotel:, params: {
      view: "timeline",
      start_date: "2026-07-16",
      room_state: "turnover",
      occupancy: "arrival"
    })

    expect(room_state.filters).to have_attributes(room_state: :turnover, occupancy: nil)
    expect(room_state.query).to include(room_state: :turnover)
    expect(room_state.query).not_to have_key(:occupancy)
    expect(timeline.filters).to have_attributes(room_state: nil, occupancy: :arrival)
    expect(timeline.query).not_to have_key(:room_state)
  end

  it "ignores room grouping outside Room View" do
    state = described_class.new(hotel:, params: { view: "timeline", start_date: "2026-07-16", group_by: "none" })

    expect(state.query).not_to have_key(:group_by)
  end

  it "uses the room date and safe defaults for invalid state" do
    state = described_class.new(hotel:, params: { view: "rooms", date: "bad", days: 30, density: "large" })

    expect(state).to have_attributes(view_mode: :rooms, density: :compact)
    expect(state.date_window).to have_attributes(start_date: Date.new(2026, 7, 16), days: 1)
    expect(state.query).to include(view: :rooms, date: Date.new(2026, 7, 16))
    expect(state.query).not_to have_key(:density)
    expect(state.query).not_to have_key(:days)
  end

  it "translates dates when switching modes" do
    state = described_class.new(hotel:, params: { view: "rooms", date: "2026-07-22", room_state: "arrival", rate_plan_id: 8 })

    expect(state.query(view: :timeline, days: 7)).to include(
      view: :timeline,
      start_date: Date.new(2026, 7, 22),
      days: 7,
      rate_plan_id: 8
    )
    expect(state.query(view: :timeline, days: 7)).not_to have_key(:room_state)
  end

  it "rebuilds canonical state from effective filters" do
    state = described_class.new(hotel:, params: {
      view: "rooms", date: "2026-07-22", rate_plan_id: 99, room_state: "arrival", physical_status: "dirty"
    })

    canonical = state.with_filters(state.filters.with(rate_plan_id: nil, physical_status: nil))

    expect(canonical.query).to include(view: :rooms, date: Date.new(2026, 7, 22), room_state: :arrival)
    expect(canonical.query).not_to have_key(:rate_plan_id)
    expect(canonical.query).not_to have_key(:physical_status)
  end
end
