# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChannelManagers::ChannexRatePlanCapability do
  let(:hotel) { create(:hotel, :per_person) }
  let(:room_type) { create(:room_type, hotel:, max_adults: 3) }
  let(:rate_plan) { create(:rate_plan, :custom, hotel:, room_type:) }
  let(:assignment) { rate_plan.room_type_rate_plans.find_by!(room_type:) }

  def add_occupancies(*adults)
    adults.each { |count| assignment.occupancy_prices.create!(adults: count, price: count * 100) }
  end

  it "supports a complete per-person occupancy ladder" do
    add_occupancies(1, 2, 3)

    result = described_class.call(rate_plan:, room_type:)

    expect(result).to be_supported
    expect(result).not_to be_flattened
    expect(result.missing_occupancies).to eq({})
  end

  it "reports missing occupancies" do
    add_occupancies(2)

    result = described_class.call(rate_plan:, room_type:)

    expect(result).to be_unsupported
    expect(result.reason).to eq("Complete the adult occupancy prices")
    expect(result.missing_occupancies).to eq(room_type.id => [ 1, 3 ])
  end

  it "marks age-banded pricing as flattened when flat channel fees exist" do
    add_occupancies(1, 2, 3)
    create(:rate_plan_age_band, rate_plan:, min_age: 0, max_age: 17)
    rate_plan.update!(channex_children_fee: 25, channex_infant_fee: 0)

    expect(described_class.call(rate_plan:, room_type:)).to be_flattened
  end

  it "supports per-room plans without an occupancy ladder" do
    per_room_hotel = create(:hotel)
    per_room_type = create(:room_type, hotel: per_room_hotel)
    per_room_plan = create(:rate_plan, :custom, hotel: per_room_hotel, room_type: per_room_type)

    expect(described_class.call(rate_plan: per_room_plan, room_type: per_room_type)).to be_supported
  end
end
