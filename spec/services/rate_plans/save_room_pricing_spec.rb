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

  describe "a derived per-guest plan", :per_person do
    let(:standard_assignment) { room_type.room_type_rate_plans.find_by!(rate_plan: room_type.standard_rate_plan) }

    before do
      [ 180, 300, 410 ].each_with_index do |price, index|
        standard_assignment.occupancy_prices.create!(adults: index + 1, price: price)
      end
    end

    def nightly(adults)
      Rates::ResolveEffectiveNightlyPrice.call(
        room_type: room_type.reload, rate_plan: rate_plan, date: Date.current + 5, adults: adults
      ).amount
    end

    it "keeps only its rule, and prices every adult count from the Standard Rate rung" do
      result = described_class.call(
        rate_plan: rate_plan,
        room_type: room_type,
        pricing: pricing(rate_mode: "derived", derive_mode: "multiplier", derive_value: "-10")
      )

      expect(result).to be_success
      expect(result.assignment.reload).to have_attributes(pricing_mode: "multiplier", pricing_value: -10.to_d)
      expect(result.assignment.occupancy_prices).to be_empty
      expect((1..3).map { |adults| nightly(adults) }).to eq([ 162.to_d, 270.to_d, 369.to_d ])
    end

    it "follows a later change to the Standard Rate without being saved again" do
      described_class.call(
        rate_plan: rate_plan,
        room_type: room_type,
        pricing: pricing(rate_mode: "derived", derive_mode: "multiplier", derive_value: "-10")
      )

      standard_assignment.occupancy_prices.find_by!(adults: 2).update!(price: 400)

      expect(nightly(2)).to eq(360.to_d)
    end

    it "drops a list stored under an earlier method" do
      assignment = create(:room_type_rate_plan, rate_plan: rate_plan, room_type: room_type)
      assignment.occupancy_prices.create!(adults: 1, price: 999)

      described_class.call(
        rate_plan: rate_plan,
        room_type: room_type,
        pricing: pricing(rate_mode: "derived", derive_mode: "offset", derive_value: "-20")
      )

      expect(assignment.reload.occupancy_prices).to be_empty
      expect(nightly(1)).to eq(160.to_d)
    end

    it "reopens as Derived with its rule" do
      described_class.call(
        rate_plan: rate_plan,
        room_type: room_type,
        pricing: pricing(rate_mode: "derived", derive_mode: "multiplier", derive_value: "-10")
      )

      reopened = HotelPortal::RatePlanRoomPricing.from_assignment(
        rate_plan.room_type_rate_plans.find_by!(room_type: room_type), room_type: room_type, sells_per_person: true
      )

      expect(reopened).to have_attributes(rate_mode: "derived", derive_mode: "multiplier", derive_value: -10.to_d)
    end

    it "refuses to derive the Standard Rate from itself" do
      result = described_class.call(
        rate_plan: room_type.standard_rate_plan,
        room_type: room_type,
        pricing: pricing(rate_mode: "derived", derive_mode: "multiplier", derive_value: "-10")
      )

      expect(result).not_to be_success
      expect(result.error).to eq("The Standard Rate can't adjust itself. Set its prices directly.")
      expect(standard_assignment.reload).to have_attributes(pricing_mode: "fixed")
    end
  end

  describe "an Auto per-guest plan", :per_person do
    let(:auto_pricing) do
      pricing(rate_mode: "auto", default_rate: "300", primary_occupancy: "2",
              increase_by: "100", increase_unit: "amount", decrease_by: "30", decrease_unit: "percent")
    end

    it "remembers the anchor and steps it was generated from, and reopens as Auto" do
      result = described_class.call(rate_plan: rate_plan, room_type: room_type, pricing: auto_pricing)

      reopened = HotelPortal::RatePlanRoomPricing.from_assignment(
        result.assignment.reload, room_type: room_type, sells_per_person: true
      )

      expect(reopened).to have_attributes(
        rate_mode: "auto", default_rate: 300.to_d, primary_occupancy: 2,
        increase_by: 100.to_d, increase_unit: "amount", decrease_by: 30.to_d, decrease_unit: "percent"
      )
      expect(reopened.prices.transform_values(&:to_d)).to eq(1 => 210.to_d, 2 => 300.to_d, 3 => 400.to_d)
    end

    it "forgets the steps once the plan is priced directly" do
      described_class.call(rate_plan: rate_plan, room_type: room_type, pricing: auto_pricing)
      result = described_class.call(
        rate_plan: rate_plan, room_type: room_type,
        pricing: pricing(rate_mode: "manual", prices: { "1" => "200", "2" => "300", "3" => "400" })
      )

      expect(result.assignment.reload.occupancy_ladder).to be_nil
      expect(HotelPortal::RatePlanRoomPricing.from_assignment(result.assignment, room_type: room_type, sells_per_person: true).rate_mode).to eq("manual")
    end
  end
end
