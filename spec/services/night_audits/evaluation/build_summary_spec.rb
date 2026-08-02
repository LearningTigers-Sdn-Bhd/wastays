require "rails_helper"

RSpec.describe NightAudits::Evaluation::BuildSummary do
  it "is the evaluator summary builder" do
    hotel = create(:hotel)
    context = NightAudits::Evaluation::Context.new(hotel: hotel, business_date: Date.current, phase: :post_close)

    expect(described_class.new(context: context).call).to include(
      "arrivals_count",
      "payment_status_counts"
    )
  end
end
