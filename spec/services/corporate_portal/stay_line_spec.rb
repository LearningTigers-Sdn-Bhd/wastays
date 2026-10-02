# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporatePortal::StayLine do
  describe ".parse" do
    it "reads the indexed shape a URL or form carries, in order" do
      parsed = described_class.parse(
        "1" => { room_type_id: "7", adults: "3", children: "1", child_ages: "6", quantity: "2" },
        "0" => { room_type_id: "5", rate_plan_id: "9", adults: "2" }
      )

      expect(parsed.map(&:room_type_id)).to eq([ 5, 7 ])
      expect(parsed.last).to have_attributes(adults: 3, children: 1, child_ages: [ 6 ], quantity: 2, rate_plan_id: nil)
    end

    it "reads an array of hashes" do
      parsed = described_class.parse([ { room_type_id: "5", adults: "2" } ])

      expect(parsed.first).to have_attributes(room_type_id: 5, adults: 2, quantity: 1, children: 0)
    end

    it "reads request parameters without needing them permitted" do
      params = ActionController::Parameters.new(lines: { "0" => { room_type_id: "5", adults: "2" } })

      expect(described_class.parse(params[:lines]).map(&:room_type_id)).to eq([ 5 ])
    end

    it "drops a line that names no category" do
      expect(described_class.parse([ { adults: "2" }, { room_type_id: "", adults: "2" } ])).to eq([])
    end

    it "keeps no more ages than children, whether they come as a list or as text" do
      from_text = described_class.parse([ { room_type_id: "5", children: "1", child_ages: "4,9,11" } ]).first
      from_list = described_class.parse([ { room_type_id: "5", children: "2", child_ages: %w[4 9 11] } ]).first

      expect(from_text.child_ages).to eq([ 4 ])
      expect(from_list.child_ages).to eq([ 4, 9 ])
    end

    it "floors the quantity at one room and children at none, but never invents an adult" do
      line = described_class.parse([ { room_type_id: "5", adults: "0", children: "-2", quantity: "0" } ]).first

      expect(line).to have_attributes(quantity: 1, children: 0, adults: 0)
    end

    it "returns nothing for nothing" do
      expect(described_class.parse(nil)).to eq([])
      expect(described_class.parse({})).to eq([])
    end
  end

  describe "#to_param_hash and .to_params" do
    let(:line) { described_class.new(room_type_id: 5, rate_plan_id: 9, adults: 2, children: 2, child_ages: [ 4, 9 ], quantity: 3) }

    it "writes child ages as one comma-separated value" do
      expect(line.to_param_hash).to include(child_ages: "4,9", quantity: 3)
    end

    it "leaves out a rate that was not chosen" do
      expect(described_class.new(room_type_id: 5, adults: 2, children: 0, child_ages: [], quantity: 1).to_param_hash).not_to have_key(:rate_plan_id)
    end

    it "round-trips through the params it puts in a URL, in order" do
      other = described_class.new(room_type_id: 6, adults: 1, children: 0, child_ages: [], quantity: 1)
      lines = [ line, other ]

      expect(described_class.to_params(lines).keys).to eq(%w[0 1])
      expect(described_class.parse(described_class.to_params(lines))).to eq(lines)
    end
  end

  it "treats lines with the same party as one occupancy" do
    a = described_class.new(room_type_id: 5, adults: 2, children: 0, child_ages: [], quantity: 2)
    b = described_class.new(room_type_id: 6, adults: 2, children: 0, child_ages: [], quantity: 2)

    expect(a.occupancy).to eq(b.occupancy)
  end
end
