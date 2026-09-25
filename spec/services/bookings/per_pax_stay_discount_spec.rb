# frozen_string_literal: true

require "rails_helper"

# Test plan phase B: number of nights and long-stay discounts.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.3, table 6b.
#
# Base nightly figure for "FB, 2A + child 8, with ages" is 620: 500 + 40% of
# the 1-adult 300 (spec/services/rates/per_pax_plan_pricing_spec.rb, P5).
RSpec.describe "Per-pax long-stay discount pricing" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 10 }

  def total_for(plan, nights, adults:, children: 0, child_ages: [])
    Bookings::CalculateStayPrice.new(
      room_type: suite, check_in: check_in, check_out: check_in + nights,
      rate_plan: plan, adults: adults, children: children, child_ages: child_ages
    ).call
  end

  def snapshot_for(plan, nights, adults:, children: 0, booking: nil)
    Bookings::BuildFinancialSnapshot.new(
      hotel: hotel, booking: booking, room_type: suite, rate_plan: plan,
      check_in: check_in, check_out: check_in + nights, guest_country: "Malaysia",
      adults: adults, children: children
    ).call
  end

  describe "B1: table 6b, FB 2A + child 8 (ages given)" do
    { 1 => 620, 2 => 1240, 3 => 1674, 4 => 2232, 5 => 2860, 7 => 3980 }.each do |nights, expected|
      it "#{nights} night(s) totals #{expected}" do
        expect(total_for(fb_plan, nights, adults: 2, children: 1, child_ages: [ 8 ])).to eq(expected.to_d)
      end
    end
  end

  it "B1 (STD, no discount rules), 7 nights: flat 4A x 740" do
    expect(total_for(std_plan, 7, adults: 4)).to eq((740 * 7).to_d)
  end

  it "B2: each discounted night carries undiscounted_price and stay_discount metadata" do
    result = snapshot_for(fb_plan, 5, adults: 2, children: 1)
    nights = result.nightly_rate_snapshot.sort.to_h.values

    expect(nights.first).not_to have_key("undiscounted_price") # night 1, from_night 2 rule not yet active
    nights[1..].each do |night|
      expect(night["undiscounted_price"]).to be_present
      expect(night["stay_discount"]).to include("min_nights" => 5, "discount_type" => "amount")
    end
  end

  it "B3: amount-off counts guests - 2A (2 guests) vs 2A+2C (4 guests) at 5 nights, 20 off per guest from night 2" do
    two_guests = snapshot_for(fb_plan, 5, adults: 2, children: 0)
    four_guests = snapshot_for(fb_plan, 5, adults: 2, children: 2)

    night2_two = two_guests.nightly_rate_snapshot.sort.to_h.values[1]
    night2_four = four_guests.nightly_rate_snapshot.sort.to_h.values[1]

    expect(night2_two["price"].to_d).to eq(night2_two["undiscounted_price"].to_d - 40) # 20 x 2 guests
    expect(night2_four["price"].to_d).to eq(night2_four["undiscounted_price"].to_d - 80) # 20 x 4 guests
  end

  it "B4: an amount-off bigger than the night floors at 0, never negative" do
    cheap_plan = create(:rate_plan, :custom, hotel: hotel, name: "Cheap Amount Off", ta_access: "hidden")
    save_manual_prices!(cheap_plan, suite, { 1 => 10, 2 => 10, 3 => 10, 4 => 10 })
    cheap_plan.rate_plan_stay_discounts.create!(min_nights: 2, discount_type: "amount", value: 500, from_night: 1)

    expect(total_for(cheap_plan, 2, adults: 1)).to eq(0.to_d)
  end

  it "B5: STD (no long-stay rules), 7 nights, has no discount" do
    result = snapshot_for(std_plan, 7, adults: 2)

    expect(result.nightly_rate_snapshot.values).to all(satisfy { |n| !n.key?("stay_discount") })
  end

  describe "B6: FB with a child whose age was not given (fallback multiplier)" do
    { 3 => 2025, 5 => 3510 }.each do |nights, expected|
      it "#{nights} nights totals #{expected}" do
        expect(total_for(fb_plan, nights, adults: 2, children: 1, child_ages: [])).to eq(expected.to_d)
      end
    end
  end

  it "B7: an OTA booking gets no long-stay discount even at 5 nights" do
    booking = create(:booking, hotel: hotel, source: "ota")
    result = Bookings::BuildFinancialSnapshot.new(
      hotel: hotel, booking: booking, room_type: suite, rate_plan: std_plan,
      check_in: check_in, check_out: check_in + 5, guest_country: "Malaysia", adults: 2
    ).call

    expect(result.nightly_rate_snapshot.values).to all(satisfy { |n| !n.key?("stay_discount") })
  end

  it "B8: applying the discount to an already-discounted nightly snapshot does not discount it twice" do
    once = Rates::ApplyStayDiscount.snapshot(
      rate_plan: fb_plan, guests: 2,
      snapshot: { "2026-10-10" => { "price" => "600.0" }, "2026-10-11" => { "price" => "600.0" }, "2026-10-12" => { "price" => "600.0" } }
    )
    twice = Rates::ApplyStayDiscount.snapshot(rate_plan: fb_plan, guests: 2, snapshot: once)

    expect(twice).to eq(once)
  end
end
