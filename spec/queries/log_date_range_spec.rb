require "rails_helper"

RSpec.describe LogDateRange do
  it "reads a full range" do
    expect(described_class.call("2026-09-01/2026-09-02")).to eq(Date.new(2026, 9, 1).beginning_of_day..Date.new(2026, 9, 2).end_of_day)
  end

  it "reads a range with one end" do
    expect(described_class.call("2026-09-10").begin).to eq(Date.new(2026, 9, 10).beginning_of_day)
    expect(described_class.call("/2026-09-10").end).to eq(Date.new(2026, 9, 10).end_of_day)
  end

  it "returns nil for blank or bad values" do
    expect(described_class.call(nil)).to be_nil
    expect(described_class.call("nope/nope")).to be_nil
  end
end
