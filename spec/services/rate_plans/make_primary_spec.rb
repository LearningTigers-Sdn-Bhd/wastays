# frozen_string_literal: true

require "rails_helper"

RSpec.describe RatePlans::MakePrimary do
  let(:hotel) { create(:hotel) }
  let(:room_type) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Deluxe", room_number_mode: "custom", quantity: 1, base_price: 250.0, max_adults: 2, room_numbers: %w[101] }
    )
  end
  let(:package) do
    create(:rate_plan, :custom, hotel: hotel, name: "Full Board").tap do |plan|
      create(:room_type_rate_plan, rate_plan: plan, room_type: room_type, pricing_value: 400)
    end
  end

  it "has no primary plan until one is picked" do
    expect(room_type.primary_rate_plan).to be_nil
  end

  it "makes an attached plan primary and moves the flag off the previous one" do
    expect(described_class.call(room_type: room_type, rate_plan: package)).to be_success
    expect(room_type.reload.primary_rate_plan).to eq(package)

    expect(described_class.call(room_type: room_type, rate_plan: room_type.standard_rate_plan)).to be_success
    expect(room_type.reload.primary_rate_plan).to eq(room_type.standard_rate_plan)
    expect(room_type.room_type_rate_plans.where(primary_plan: true).count).to eq(1)
  end

  it "keeps Standard as the pricing anchor when another plan is primary" do
    standard = room_type.standard_rate_plan
    described_class.call(room_type: room_type, rate_plan: package)

    expect(room_type.reload.standard_rate_plan).to eq(standard)
  end

  it "refuses a plan the booking site never sells" do
    result = described_class.call(room_type: room_type, rate_plan: room_type.walk_in_rate_plan)

    expect(result).not_to be_success
    expect(result.error).to include("booking site")
  end

  it "stops leading with a plan once it is archived" do
    described_class.call(room_type: room_type, rate_plan: package)
    package.archive!

    expect(room_type.reload.primary_rate_plan).to be_nil
  end
end
