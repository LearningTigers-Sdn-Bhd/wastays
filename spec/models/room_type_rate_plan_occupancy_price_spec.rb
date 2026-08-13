require "rails_helper"

RSpec.describe RoomTypeRatePlanOccupancyPrice, type: :model do
  let(:room_type) { create(:room_type, max_adults: 2) }
  let(:assignment) { create(:room_type_rate_plan, room_type: room_type, rate_plan: create(:rate_plan, :custom, hotel: room_type.hotel)) }

  it "stores one non-negative price per adult occupancy" do
    described_class.create!(room_type_rate_plan: assignment, adults: 1, price: 180)
    duplicate = described_class.new(room_type_rate_plan: assignment, adults: 1, price: 200)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:adults]).to be_present
  end

  it "rejects an occupancy above the room category's adult capacity" do
    price = described_class.new(room_type_rate_plan: assignment, adults: 3, price: 300)

    expect(price).not_to be_valid
    expect(price.errors[:adults]).to include("cannot exceed the room category's maximum adults")
  end
end
