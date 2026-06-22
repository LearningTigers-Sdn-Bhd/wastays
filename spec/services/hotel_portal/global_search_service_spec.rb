require "rails_helper"

RSpec.describe HotelPortal::GlobalSearchService do
  let(:plan) { create(:plan) }
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:hotel) { create(:hotel, plan: plan) }
  let!(:booking) { create(:booking, hotel: hotel, guest_name: "Sam", confirmation_token: "WS-SAM01") }

  before do
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
  end

  it "includes pages for empty query" do
    results = described_class.new(hotel, "").perform
    expect(results).to include(hash_including(title: "Arrival Board", group: "Pages"))
    expect(results).to include(hash_including(title: "Folios", group: "Pages"))
  end

  it "returns booking result for matching query" do
    results = described_class.new(hotel, "sam").perform
    expect(results).to include(hash_including(title: a_string_including("WS-SAM01"), group: "Bookings"))
  end

  it "excludes AI concierge pages when excluded from plan" do
    plan.plan_features.find_by!(feature: ai_concierge_page_feature).update!(enabled: false)

    results = described_class.new(hotel, "").perform

    expect(results).not_to include(hash_including(title: "Policy Management"))
    expect(results).not_to include(hash_including(title: "FAQs Management"))
    expect(results).not_to include(hash_including(title: "General Info Management"))
  end
end
