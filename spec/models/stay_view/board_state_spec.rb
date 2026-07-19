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
      occupancy: "arrival"
    })

    expect(state).to have_attributes(view_mode: :timeline, density: :compact)
    expect(state.date_window).to have_attributes(start_date: Date.new(2026, 7, 20), days: 21)
    expect(state.filters.occupancy).to eq(:arrival)
    expect(state.query).to include(view: :timeline, start_date: Date.new(2026, 7, 20), days: 21, occupancy: :arrival)
    expect(state.query).not_to have_key(:density)
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
    state = described_class.new(hotel:, params: { view: "rooms", date: "2026-07-22", room_state: "arrival" })

    expect(state.query(view: :timeline, days: 7)).to include(
      view: :timeline,
      start_date: Date.new(2026, 7, 22),
      days: 7
    )
    expect(state.query(view: :timeline, days: 7)).not_to have_key(:room_state)
  end
end
