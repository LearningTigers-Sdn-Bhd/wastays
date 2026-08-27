require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Sales::NextAction do
  it "accepts every supported kind" do
    described_class::KINDS.each do |kind|
      expect(described_class.new(kind).kind).to eq(kind)
    end
  end

  it "rejects an unsupported kind" do
    expect { described_class.new("invented") }
      .to raise_error(ArgumentError, "Unsupported next action: invented")
  end

  it "identifies the empty action" do
    expect(described_class.none).to be_none
    expect(described_class.new("offer_booking_help")).not_to be_none
  end

  it "identifies only the two optional sales offers" do
    expect(described_class.new("offer_booking_help")).to be_optional
    expect(described_class.new("offer_price_search")).to be_optional
    expect(described_class.new("resume_booking")).not_to be_optional
  end
end
