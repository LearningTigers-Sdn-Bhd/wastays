require "rails_helper"

RSpec.describe RatePlans::SaveRoomPricing do
  let(:hotel) do
    create(:hotel, sell_mode: RSpec.current_example.metadata[:per_person] ? "per_person" : "per_room")
  end
  let(:room_type) { create(:room_type, hotel: hotel, max_adults: 3, base_price: 300) }
  let(:rate_plan) { create(:rate_plan, :custom, hotel: hotel) }

  def pricing(attrs)
    HotelPortal::RatePlanRoomPricing.from_h(
      attrs,
      room_type: room_type,
      sells_per_person: hotel.sells_per_person?
    )
  end

  it "persists a fixed per-room starting price" do
    result = described_class.call(
      rate_plan: rate_plan,
      room_type: room_type,
      pricing: pricing(rate_mode: "manual", default_rate: "240")
    )

    expect(result).to be_success
    expect(result.assignment).to have_attributes(pricing_mode: "fixed", pricing_value: 240.to_d)
    expect(result.assignment.occupancy_prices).to be_empty
  end

  it "persists a live per-room Standard Rate adjustment" do
    result = described_class.call(
      rate_plan: rate_plan,
      room_type: room_type,
      pricing: pricing(rate_mode: "derived", derive_mode: "multiplier", derive_value: "-15")
    )

    expect(result).to be_success
    expect(result.assignment).to have_attributes(pricing_mode: "multiplier", pricing_value: -15.to_d)
  end

  it "materializes and replaces a complete per-guest occupancy matrix", :per_person do
    assignment = create(:room_type_rate_plan, rate_plan: rate_plan, room_type: room_type)
    assignment.occupancy_prices.create!(adults: 1, price: 999)

    result = described_class.call(
      rate_plan: rate_plan,
      room_type: room_type,
      pricing: pricing(
        rate_mode: "auto",
        default_rate: "300",
        primary_occupancy: "2",
        decrease_by: "80",
        decrease_unit: "amount",
        increase_by: "100",
        increase_unit: "amount"
      )
    )

    expect(result).to be_success
    expect(result.assignment.reload).to have_attributes(pricing_mode: "fixed", pricing_value: nil)
    expect(result.assignment.occupancy_prices.order(:adults).pluck(:adults, :price)).to eq([
      [ 1, 220.to_d ], [ 2, 300.to_d ], [ 3, 400.to_d ]
    ])
  end

  it "refuses an incomplete direct per-guest matrix without writing", :per_person do
    result = described_class.call(
      rate_plan: rate_plan,
      room_type: room_type,
      pricing: pricing(rate_mode: "manual", prices: { "1" => "100", "2" => "180", "3" => "" })
    )

    expect(result).not_to be_success
    expect(result.error).to include("3 adults")
    expect(rate_plan.room_type_rate_plans.where(room_type: room_type)).to be_empty
  end
end
