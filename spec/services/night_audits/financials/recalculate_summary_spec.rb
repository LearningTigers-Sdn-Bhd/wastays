require "rails_helper"

RSpec.describe NightAudits::Financials::RecalculateSummary do
  it "backs the public recalculation service" do
    hotel = create(:hotel)
    attributes = { hotel: hotel, business_date: Date.current, user: nil, reason: "Test" }

    expect(described_class.new(**attributes).call).to eq(NightAudits::RecalculateFinancialSummary.new(**attributes).call)
  end
end
