# frozen_string_literal: true

require "rails_helper"

# Test plan phase P: price per guest count.
# docs/wastays/per-pax-ta-reservations-test-plan-2026-09-25.md §7.2, table 6a.
RSpec.describe "Per-pax plan pricing by guest count" do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 10 }
  let(:check_out) { check_in + 1 }

  def price(plan, adults:, children: 0, child_ages: [])
    Bookings::CalculateStayPrice.new(
      room_type: suite, check_in: check_in, check_out: check_out,
      rate_plan: plan, adults: adults, children: children, child_ages: child_ages
    ).call
  end

  # P1-P4: 1..4 adults across all four plans
  describe "adult counts" do
    {
      std: { plan: -> { std_plan }, prices: { 1 => 250, 2 => 440, 3 => 600, 4 => 740 } },
      fb: { plan: -> { fb_plan }, prices: { 1 => 300, 2 => 500, 3 => 690, 4 => 840 } },
      corp: { plan: -> { corp_plan }, prices: { 1 => 225, 2 => 396, 3 => 540, 4 => 666 } },
      prm: { plan: -> { prm_plan }, prices: { 1 => 336, 2 => 480, 3 => 630, 4 => 780 } }
    }.each do |name, config|
      config[:prices].each do |adults, expected|
        it "prices #{name.upcase} at #{adults} adult(s) as #{expected}" do
          expect(price(instance_exec(&config[:plan]), adults: adults)).to eq(expected.to_d)
        end
      end
    end
  end

  # P5: a multiplier band is a share of the plan's 1-adult list price (300),
  # not of the party's per-adult share (500 / 2) - 40% of 300 = 120.
  it "P5: FB, 2 adults + child 8 with age given, is 500 + 40% of the 1-adult price (300) = 620" do
    expect(price(fb_plan, adults: 2, children: 1, child_ages: [ 8 ])).to eq(620.to_d)
  end

  # P6: 2A + teen 14 -> FB 650; 2A + child 8 + teen 14 -> 770
  it "P6a: FB, 2 adults + teen 14 with age given, is 500 + 150 = 650" do
    expect(price(fb_plan, adults: 2, children: 1, child_ages: [ 14 ])).to eq(650.to_d)
  end

  it "P6b: FB, 2 adults + child 8 + teen 14, is 500 + 120 + 150 = 770" do
    expect(price(fb_plan, adults: 2, children: 2, child_ages: [ 8, 14 ])).to eq(770.to_d)
  end

  # P7: 2A + 1 child without an age falls back to the plan's child multiplier
  it "P7: FB, 2 adults + 1 child with NO ages, is charged a full adult share: 750, not the banded 620" do
    result = price(fb_plan, adults: 2, children: 1, child_ages: [])

    expect(result).to eq(750.to_d) # no age given: the 1.0 fallback multiplier applies, not the age band
  end

  # P8 / R13: a child whose age fits no band (bands start at 4)
  it "P8 (R13): FB, 2 adults + child 2 with age given (no band covers age 2), falls back to a full adult share: 750" do
    expect(price(fb_plan, adults: 2, children: 1, child_ages: [ 2 ])).to eq(750.to_d) # RECORDED: R13
  end

  # P9 / R10: more adults than the list covers
  it "P9 (R10): 5 adults on the Suite (list only covers up to 4) has no price" do
    expect(price(std_plan, adults: 5)).to be_nil
  end

  # P10: ages count doesn't match children count -> ages ignored, fallback pricing used
  it "P10: FB, 2 adults + 2 children but only 1 age given, ignores ages entirely (falls back to 1.0 multiplier for both)" do
    with_ages = price(fb_plan, adults: 2, children: 2, child_ages: [ 8 ])
    without_ages = price(fb_plan, adults: 2, children: 2, child_ages: [])

    expect(with_ages).to eq(without_ages)
    expect(with_ages).to eq(500 + (2 * 250).to_d) # 2 children x (500/2 adults) x 1.0 multiplier
  end

  # P11: band boundaries
  describe "P11: band boundaries" do
    { 3 => 750, 4 => 620, 11 => 620, 12 => 650, 17 => 650, 18 => 750 }.each do |age, expected|
      it "age #{age} prices at #{expected}" do
        expect(price(fb_plan, adults: 2, children: 1, child_ages: [ age ])).to eq(expected.to_d)
      end
    end
  end

  # P12: a room-specific band price overrides the band's own figure. The
  # override's mode always follows the band's own pricing_mode (there is no
  # mode column on the override row itself) - an amount band's override is a
  # flat replacement amount, so this uses the (amount-mode) Teen band.
  it "P12: a room-specific age band price on the FB-Suite pairing overrides the band's own amount" do
    assignment = fb_plan.room_type_rate_plans.find_by!(room_type: suite)
    teen_band = fb_plan.rate_plan_age_bands.find_by!(min_age: 12, max_age: 17)

    assignment.age_band_prices.create!(rate_plan_age_band: teen_band, price: 80)

    expect(price(fb_plan, adults: 2, children: 1, child_ages: [ 14 ])).to eq((500 + 80).to_d)
  end
end
