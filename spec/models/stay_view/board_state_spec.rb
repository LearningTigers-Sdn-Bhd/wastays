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

  it "uses the room date and safe defaults for invalid state" do
    state = described_class.new(hotel:, params: { view: "rooms", date: "bad", days: 30, density: "large" })

    expect(state).to have_attributes(view_mode: :rooms, density: :compact)
    expect(state.date_window).to have_attributes(start_date: Date.new(2026, 7, 16), days: 1)
    expect(state.query).to include(view: :rooms, date: Date.new(2026, 7, 16))
    expect(state.query).not_to have_key(:density)
    expect(state.query).not_to have_key(:days)
  end

  it "translates dates when switching modes" do
    state = described_class.new(hotel:, params: { view: "rooms", date: "2026-07-22" })

    expect(state.query(view: :timeline, days: 7)).to include(
      view: :timeline,
      start_date: Date.new(2026, 7, 22),
      days: 7
    )
  end
end
