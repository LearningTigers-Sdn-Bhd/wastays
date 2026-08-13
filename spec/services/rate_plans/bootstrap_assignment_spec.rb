# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePlans::BootstrapAssignment do
  it "makes a per-room assignment follow its room's Standard Rate" do
    hotel = create(:hotel)
    room = create(:room_type, hotel: hotel, base_price: 240)
    plan = create(:rate_plan, :custom, hotel: hotel)

    assignment = described_class.call!(rate_plan: plan, room_type: room)

    expect(assignment).to have_attributes(pricing_mode: "multiplier", pricing_value: 0.to_d)
    expect(assignment.occupancy_prices).to be_empty
  end

  it "copies a complete per-person Standard Rate occupancy ladder" do
    hotel = create(:hotel, :per_person)
    room = create(:room_type, hotel: hotel, max_adults: 3, base_price: 100)
    standard_assignment = room.room_type_rate_plans.find_by!(rate_plan: room.standard_rate_plan)
    standard_assignment.occupancy_prices.create!(adults: 1, price: 90)
    standard_assignment.occupancy_prices.create!(adults: 2, price: 170)
    standard_assignment.occupancy_prices.create!(adults: 3, price: 240)
    plan = create(:rate_plan, :custom, hotel: hotel)

    assignment = described_class.call!(rate_plan: plan, room_type: room)

    expect(assignment).to have_attributes(pricing_mode: "fixed", pricing_value: nil)
    expect(assignment.occupancy_prices.order(:adults).pluck(:adults, :price)).to eq([
      [ 1, 90.to_d ], [ 2, 170.to_d ], [ 3, 240.to_d ]
    ])
  end

  it "fills a missing Standard ladder with the room's existing per-person fallback" do
    hotel = create(:hotel, :per_person)
    room = create(:room_type, hotel: hotel, max_adults: 2, base_price: 125)
    plan = create(:rate_plan, :custom, hotel: hotel)

    assignment = described_class.call!(rate_plan: plan, room_type: room)

    expect(assignment.occupancy_prices.order(:adults).pluck(:adults, :price)).to eq([
      [ 1, 125.to_d ], [ 2, 250.to_d ]
    ])
  end
end
