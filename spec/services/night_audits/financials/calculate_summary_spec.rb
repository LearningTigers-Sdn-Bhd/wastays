require "rails_helper"

RSpec.describe NightAudits::Financials::CalculateSummary do
  it "backs the public financial summary service" do
    hotel = create(:hotel)

    expect(described_class.call(hotel: hotel, business_date: Date.current)).to eq(
      NightAudits::CalculateFinancialSummary.call(hotel: hotel, business_date: Date.current)
    )
  end
end
