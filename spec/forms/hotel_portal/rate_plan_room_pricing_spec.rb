# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::RatePlanRoomPricing, "#example_price" do
  let(:room_type) { instance_double(RoomType, base_price: 200, max_adults: 3, standard_rate_plan: nil, room_type_rate_plans: RoomTypeRatePlan.none) }

  def pricing(attrs, per_person: false)
    described_class.from_h(attrs, room_type: room_type, sells_per_person: per_person)
  end

  it "uses the fixed rate for a per-room plan" do
    expect(pricing({ rate_mode: "manual", default_rate: "150" }).example_price).to eq(150)
  end

  it "applies the adjustment to the category's standard rate for a derived per-room plan" do
    expect(pricing({ rate_mode: "derived", derive_mode: "multiplier", derive_value: "10" }).example_price).to eq(220)
    expect(pricing({ rate_mode: "derived", derive_mode: "offset", derive_value: "-30" }).example_price).to eq(170)
  end

  it "is nil when nothing usable has been entered" do
    expect(pricing({ rate_mode: "manual" }).example_price).to be_nil
  end

  it "reads a manual per-person plan at two adults" do
    price = pricing({ rate_mode: "manual", prices: { "1" => "100", "2" => "160", "3" => "210" } }, per_person: true)

    expect(price.example_price).to eq(160)
  end

  it "reads an auto per-person plan at its primary occupancy" do
    price = pricing({ rate_mode: "auto", default_rate: "180", primary_occupancy: 2 }, per_person: true)

    expect(price.example_price).to eq(180)
  end

  it "clamps the occupancy to what the room fits" do
    price = pricing({ rate_mode: "manual", primary_occupancy: 5, prices: { "1" => "100", "2" => "160", "3" => "210" } }, per_person: true)

    expect(price.example_price).to eq(210)
  end
end
