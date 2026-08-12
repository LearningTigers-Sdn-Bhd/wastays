# frozen_string_literal: true

require "rails_helper"

RSpec.describe Rates::SetupCoverage do
  let(:hotel) { create(:hotel) }
  let(:room) { create(:room_type, hotel: hotel, quantity: 3, base_price: 120, max_adults: 2) }
  let(:start_date) { Date.current }
  let(:end_date) { start_date + 2.days }

  it "counts explicit closed dates as configured but not sellable" do
    create(:room_inventory, room_type: room, date: start_date, quantity: 3, status: "open")
    create(:room_inventory, room_type: room, date: start_date + 1.day, quantity: 0, status: "closed")

    result = described_class.call(hotel: hotel, start_date: start_date, end_date: end_date)

    expect(result).to have_attributes(total_days: 3, configured_days: 2, sellable_days: 1)
    expect(result.configured_percentage).to eq(66.67)
    expect(result.sellable_percentage).to eq(33.33)
    expect(result.expires_on).to eq(start_date + 1.day)
    expect(result.gaps).to include(include(type: "missing_inventory", dates: [ end_date ]))
  end

  it "requires every supported adult occupancy on an open per-person date" do
    pax_hotel = create(:hotel, :per_person)
    pax_room = create(:room_type, hotel: pax_hotel, quantity: 1, max_adults: 2)
    standard = pax_room.standard_rate_plan
    assignment = pax_room.room_type_rate_plans.find_by!(rate_plan: standard)
    assignment.occupancy_prices.create!(adults: 1, price: 100)
    create(:room_inventory, room_type: pax_room, date: start_date, quantity: 1, status: "open")

    result = described_class.call(hotel: pax_hotel, start_date: start_date, end_date: start_date)

    expect(result.sellable_days).to eq(0)
    expect(result.gaps).to include(include(type: "unsellable", dates: [ start_date ]))
  end
end
