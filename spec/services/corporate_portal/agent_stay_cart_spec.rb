# frozen_string_literal: true

require "rails_helper"

# A stay is a list of lines: rooms of one category, on one rate, for one party. The
# cart prices each line for its own party and checks the stay as a whole.
RSpec.describe CorporatePortal::AgentStayCart do
  include_context "per-pax resort"

  let(:check_in) { Date.current + 20 }
  let(:check_out) { check_in + 1 }

  def line(room_type:, plan:, adults: 2, children: 0, quantity: 1, child_ages: [])
    CorporatePortal::StayLine.new(room_type_id: room_type.id, rate_plan_id: plan.id, adults: adults, children: children,
                                  child_ages: child_ages, quantity: quantity)
  end

  def cart(lines, relationship: ta_a)
    described_class.call(hotel: hotel, relationship: relationship, check_in: check_in, check_out: check_out, lines: lines)
  end

  it "prices each line for its own party, across categories" do
    result = cart([ line(room_type: suite, plan: std_plan, adults: 4), line(room_type: twin, plan: std_plan, adults: 2) ])

    expect(result).to be_success
    expect(result.quotes.map(&:per_room_amount)).to eq([ 740, 350 ])
    expect(result.rooms).to eq(2)
    expect(result.total_amount).to eq(740 + 350)
  end

  it "multiplies a line's price by its quantity" do
    result = cart([ line(room_type: suite, plan: std_plan, adults: 2, quantity: 2) ])

    expect(result.quotes.first.total_amount).to eq(880)
    expect(result.rooms).to eq(2)
  end

  it "lets the stay mix rate plans, each one the agency may book" do
    result = cart([ line(room_type: suite, plan: std_plan, adults: 2), line(room_type: suite, plan: fb_plan, adults: 2) ])

    expect(result).to be_success
    expect(result.quotes.map { |quote| quote.rate_plan.name }).to eq([ std_plan.name, "Full Board" ])
    expect(result.quotes.map(&:per_room_amount)).to eq([ 440, 500 ])
  end

  it "refuses a rate the agency is not offered, naming the problem line" do
    result = cart([ line(room_type: suite, plan: std_plan), line(room_type: suite, plan: fb_plan) ], relationship: ta_b)

    expect(result).not_to be_success
    expect(result.errors).to include("Choose a rate plan.")
    expect(result.quotes.map(&:ok?)).to eq([ true, false ])
  end

  it "refuses a rate from the other market" do
    ta_a.update!(market: "local")
    std_plan.update!(ta_market: "international")

    expect(cart([ line(room_type: suite, plan: std_plan) ]).errors).to include("Choose a rate plan.")
  end

  it "counts the lines of one category against the same free rooms" do
    # The suite has three rooms: two lines of two cannot both be had.
    result = cart([ line(room_type: suite, plan: std_plan, quantity: 2), line(room_type: suite, plan: fb_plan, quantity: 2) ])

    expect(result).not_to be_success
    expect(result.errors).to include("#{suite.name} no longer has 4 rooms free for these dates.")
  end

  it "does not let one category's rooms count against another's" do
    result = cart([ line(room_type: suite, plan: std_plan, quantity: 3), line(room_type: twin, plan: std_plan, quantity: 2) ])

    expect(result).to be_success
  end

  it "refuses a party the category cannot hold, for that line alone" do
    result = cart([ line(room_type: twin, plan: std_plan, adults: 3), line(room_type: suite, plan: std_plan) ])

    expect(result.quotes.map(&:ok?)).to eq([ false, true ])
    expect(result.errors.first).to eq(twin.occupancy_limit_message)
  end

  it "refuses a stay with no rooms" do
    expect(cart([])).not_to be_success
    expect(cart([]).errors).to eq([ "Add at least one room." ])
  end

  it "refuses dates in the past" do
    result = described_class.call(hotel: hotel, relationship: ta_a, check_in: Date.current - 3, check_out: Date.current - 2,
                                  lines: [ line(room_type: suite, plan: std_plan) ])

    expect(result.errors).to include("Arrival cannot be in the past.")
  end
end
