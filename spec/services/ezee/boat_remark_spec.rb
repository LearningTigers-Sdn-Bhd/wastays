# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ezee::BoatRemark do
  def parse(text) = described_class.call(text)

  it "reads a time with no keyword as the resort boat" do
    result = parse("(1) BOAT IN : 1030 / BOAT OUT : 1130")

    expect(result[:boat_in]).to have_attributes(type: "provided", time: "10:30")
    expect(result[:boat_out]).to have_attributes(type: "provided", time: "11:30")
  end

  it "reads OWN BOAT as the guest's own boat, with no time" do
    result = parse("(1) BOAT IN : OWN BOAT / BOAT OUT : 1430")

    expect(result[:boat_in]).to have_attributes(type: "own", time: nil)
    expect(result[:boat_out]).to have_attributes(type: "provided", time: "14:30")
  end

  it "reads a time marked (CHARTER) as a charter with that time" do
    result = parse("(1) BOAT IN : 1800(CHARTER) / BOAT OUT : OWN BOAT")

    expect(result[:boat_in]).to have_attributes(type: "charter", time: "18:00")
    expect(result[:boat_out]).to have_attributes(type: "own")
  end

  it "reads the multi-line 'BOAT IN TIME' spelling" do
    result = parse("(1) BOAT IN TIME : OWN BOAT\nBOAT OUT TIME : 0930")

    expect(result[:boat_in]).to have_attributes(type: "own")
    expect(result[:boat_out]).to have_attributes(type: "provided", time: "09:30")
  end

  it "reads colon times and a missing colon after OUT" do
    result = parse("(1) BOAT IN : 15:30 / BOAT OUT 14:30")

    expect(result[:boat_in].time).to eq("15:30")
    expect(result[:boat_out].time).to eq("14:30")
  end

  it "leaves an empty half nil instead of guessing" do
    expect(parse("(1) BOAT IN : 1030 / BOAT OUT :")).to include(boat_out: nil)
    expect(parse("(1) BOAT IN : 1030")[:boat_out]).to be_nil
  end

  it "ignores remarks that carry no boat times" do
    expect(parse("Return Boat Transfer Service 2 + Free Lunch")).to eq(boat_in: nil, boat_out: nil)
    expect(parse(nil)).to eq(boat_in: nil, boat_out: nil)
  end
end
