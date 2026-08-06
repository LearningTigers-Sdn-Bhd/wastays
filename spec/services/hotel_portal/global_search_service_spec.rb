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
    expect(results).to include(hash_including(title: "Front Desk", group: "Pages", url: Rails.application.routes.url_helpers.hotel_front_desk_path(hotel)))
    expect(results).to include(hash_including(title: "Folios", group: "Pages"))
  end

  it "returns renamed and settings-hub navigation destinations" do
    expect(described_class.new(hotel, "departures").perform).to include(hash_including(title: "Front Desk", group: "Pages", url: Rails.application.routes.url_helpers.hotel_front_desk_path(hotel)))
    expect(described_class.new(hotel, "timeline board").perform).to include(hash_including(title: "Stay View", group: "Pages"))
    expect(described_class.new(hotel, "plan billing").perform).to include(hash_including(title: "Plan & Billing", group: "Pages"))
    expect(described_class.new(hotel, "transaction codes").perform).to include(hash_including(title: "Transaction Code Reference", group: "Pages"))
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

  # perform caps at twenty rows, so these ask for the page by name rather than
  # scanning an unscored empty-query list that truncates before reaching it.
  describe "layer awareness" do
    it "marks pages outside the asking layer so the palette opens them in a new tab" do
      operations = ->(query) { described_class.new(hotel, query, layer: :operations).perform }

      expect(operations.call("front desk")).to include(hash_including(title: "Front Desk", external: false))
      expect(operations.call("folios ledger")).to include(hash_including(title: "Folios", external: true))
      expect(operations.call("reports financial performance")).to include(hash_including(title: "Reports", external: true))
    end

    it "keeps same-layer pages in place" do
      reports = ->(query) { described_class.new(hotel, query, layer: :reports).perform }

      expect(reports.call("reports financial performance")).to include(hash_including(title: "Reports", external: false))
      expect(reports.call("payouts settlements")).to include(hash_including(title: "Payouts", external: false))
      expect(reports.call("front desk")).to include(hash_including(title: "Front Desk", external: true))
    end

    it "leaves pages with no layer of their own opening in place" do
      results = described_class.new(hotel, "help support", layer: :reports).perform

      expect(results).to include(hash_including(title: "Help & Support", external: false))
    end
  end

  describe "permission filtering" do
    let(:account) { create(:account) }
    let(:hotel) { create(:hotel, account: account, plan: plan) }
    let(:user) { create(:user, account: account, role: "admin") }
    let(:role) { create(:role, account: account) }

    before do
      permission = Permission.find_by(slug: "view_bookings") || create(:permission, name: "View Bookings", slug: "view_bookings")
      create(:role_permission, role: role, permission: permission)
      create(:user_hotel_access, user: user, hotel: hotel, role: role)
    end

    it "offers only pages the user can actually open" do
      permitted = ->(query) { described_class.new(hotel, query, user: user).perform }

      expect(permitted.call("front desk")).to include(hash_including(title: "Front Desk"))
      expect(permitted.call("reports financial performance")).not_to include(hash_including(title: "Reports"))
      expect(permitted.call("staff management")).not_to include(hash_including(title: "Staff Management"))
      expect(permitted.call("audit logs operation")).not_to include(hash_including(title: "Operation Logs"))
    end

    it "filters nothing when no user is supplied" do
      results = described_class.new(hotel, "reports financial performance").perform

      expect(results).to include(hash_including(title: "Reports"))
    end
  end

  it "excludes AI concierge pages when excluded from plan" do
    plan.plan_features.find_by!(feature: ai_concierge_page_feature).update!(enabled: false)

    results = described_class.new(hotel, "").perform

    expect(results).not_to include(hash_including(title: "Policies"))
    expect(results).not_to include(hash_including(title: "FAQs"))
    expect(results).not_to include(hash_including(title: "General Info"))
  end
end
