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

  it "returns renamed and settings-hub navigation destinations" do
    expect(described_class.new(hotel, "departures").perform).to include(hash_including(title: "Departures", group: "Pages"))
    expect(described_class.new(hotel, "timeline board").perform).to include(hash_including(title: "Timeline Board", group: "Pages"))
    expect(described_class.new(hotel, "plan billing").perform).to include(hash_including(title: "Plan & Billing", group: "Pages"))
    expect(described_class.new(hotel, "transaction codes").perform).to include(hash_including(title: "Transaction Codes", group: "Pages"))
    expect(described_class.new(hotel, "general ledger").perform).to include(hash_including(title: "General Ledger Mappings", group: "Pages"))
    expect(described_class.new(hotel, "staff management").perform).to include(hash_including(title: "Staff Management", group: "Pages"))
  end

  it "returns booking result for matching query" do
    results = described_class.new(hotel, "sam").perform
    expect(results).to include(hash_including(title: a_string_including("WS-SAM01"), group: "Bookings"))
  end

  it "returns canonical resource URLs for hotel details and taxes" do
    routes = Rails.application.routes.url_helpers

    expect(described_class.new(hotel, "hotel details").perform)
      .to include(hash_including(title: "Hotel Details", url: routes.edit_hotel_profile_path(hotel)))
    expect(described_class.new(hotel, "taxes fees").perform)
      .to include(hash_including(title: "Taxes & Fees", url: routes.hotel_taxes_fees_path(hotel)))
  end

  it "excludes AI concierge pages when excluded from plan" do
    plan.plan_features.find_by!(feature: ai_concierge_page_feature).update!(enabled: false)

    results = described_class.new(hotel, "").perform

    expect(results).not_to include(hash_including(title: "Policies"))
    expect(results).not_to include(hash_including(title: "FAQs"))
    expect(results).not_to include(hash_including(title: "General Info"))
  end
end
