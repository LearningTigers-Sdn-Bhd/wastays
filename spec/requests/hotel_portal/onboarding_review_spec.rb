# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel onboarding review page", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account:, status: "setup", city: "Kota Belud", country: "Malaysia", default_currency: "MYR") }
  let(:user) { create(:user, account:, name: "Platform Admin") }
  let(:role) { create(:role, account:) }
  let(:coverage) { instance_double(Rates::SetupCoverage::Result) }
  let(:warnings) { [] }
  let(:readiness) { Onboarding::Readiness::Result.new(ready: true, blocking_issues: [], warnings:) }
  let(:snapshot) do
    {
      "property" => { "city" => "Kota Belud", "country" => "Malaysia", "default_currency" => "MYR" },
      "sections" => Onboarding::SectionCatalog.keys.index_with { |key| { "state" => key == "staff_setup" ? "skipped" : "complete" } },
      "staff" => [], "taxes" => [], "room_revenue" => {},
      "rooms" => [ { "name" => "Garden Room", "quantity" => 4 } ],
      "rates" => { "coverage" => { "end_date" => "2027-08-12" }, "plans" => [] },
      "commercial" => {
        "extra_charges" => [], "discounts" => [], "payment_methods" => [ { "name" => "Cash" } ],
        "corporate_accounts" => []
      },
      "ota_handover" => []
    }
  end
  let(:snapshot_result) do
    Onboarding::SubmissionSnapshot::Result.new(data: snapshot, digest: Digest::SHA256.hexdigest(snapshot.to_json))
  end

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role:, permission:)
    create(:user_hotel_access, user:, hotel:, role:)
    sign_in_as(user)

    Onboarding::InitializeProgress.new(hotel:).call
    hotel.onboarding_sections.update_all(state: "complete", completed_at: Time.current)
    hotel.onboarding_sections.find_by!(section_key: "staff_setup").update!(state: "skipped")

    allow(Rates::SetupCoverage).to receive(:call).with(hotel:).and_return(coverage)
    allow(Onboarding::Readiness).to receive(:new).with(hotel:, rates_coverage: coverage)
                                                  .and_return(instance_double(Onboarding::Readiness, call: readiness))
    allow(Onboarding::SubmissionSnapshot).to receive(:call).with(hotel:, rates_coverage: coverage).and_return(snapshot_result)
  end

  def get_review
    get hotel_onboarding_section_path(hotel, section_key: "review")
  end

  it "renders a compact ready review with metrics, a grouped table, and mobile rows" do
    get_review

    expect(response).to have_http_status(:ok)
    document = response.parsed_body
    expect(document.css("h1").map { |heading| heading.text.strip }).to eq([ "Review & submit" ])
    expect(document.css(".panel-alert[role='status']").text).to include("Ready to submit")
    expect(document.css("article.panel-metric-card").size).to eq(4)
    expect(document.css("div.hidden.md\\:block table.panel-table").size).to eq(1)
    expect(document.css("table caption").text).to include("Property setup summary")
    expect(document.css("table tbody th[scope='rowgroup']").map { |cell| cell.text.strip })
      .to eq([ "Property", "Team", "Finance", "Rooms & rates", "Commercial" ])
    expect(document.css("table tbody th[scope='row']").size).to eq(13)
    expect(document.css("div.md\\:hidden[aria-label='Property setup summary for small screens'] li").size).to eq(13)
    expect(response.body).to include(
      "Kota Belud, Malaysia · MYR", "Coverage through 12 Aug 2027",
      "No additional staff", "Deferred", "0 send · 0 hold"
    )
    expect(response.body).not_to include("Step 13 of 13")
    expect(document.at_css("button[type='submit'][form='onboarding-submission-form']")["disabled"]).to be_nil
  end

  it "shows blocking sections and disables submission" do
    finding = Onboarding::Readiness::Finding.new(
      section_key: "rooms", severity: :blocking, code: :rooms_invalid,
      message: "Add at least one operationally valid room type."
    )
    blocked = Onboarding::Readiness::Result.new(ready: false, blocking_issues: [ finding ], warnings: [])
    allow(Onboarding::Readiness).to receive(:new).with(hotel:, rates_coverage: coverage)
                                                  .and_return(instance_double(Onboarding::Readiness, call: blocked))

    get_review

    document = response.parsed_body
    expect(document.css(".panel-alert[role='status']").text).to include("Setup needs attention", "Resolve 1 section")
    expect(document.css("a").any? { |link| link.text.strip == "Fix" }).to be(true)
    expect(document.at_css("button[type='submit'][form='onboarding-submission-form']")["disabled"]).not_to be_nil
  end

  it "shows requested-change copy and resubmission action" do
    hotel.onboarding_sections.find_by!(section_key: "rooms").update!(state: "needs_attention")
    hotel.onboarding_sections.find_by!(section_key: "review").update!(state: "needs_attention")
    create(
      :onboarding_submission, hotel:, submitted_by: user, status: "changes_requested", snapshot:,
      reviewed_by: user, reviewed_at: Time.current, review_explanation: "Correct the room capacity."
    )
    finding = Onboarding::Readiness::Finding.new(
      section_key: "rooms", severity: :blocking, code: :needs_attention,
      message: "Review the requested changes in this section."
    )
    requested = Onboarding::Readiness::Result.new(ready: false, blocking_issues: [ finding ], warnings: [])
    allow(Onboarding::Readiness).to receive(:new).with(hotel:, rates_coverage: coverage)
                                                  .and_return(instance_double(Onboarding::Readiness, call: requested))

    get_review

    expect(response.body).to include("Changes requested", "Correct the room capacity.", "Submit changes for review")
    expect(response.parsed_body.css("article.panel-metric-card").first.text).to include("Needs attention", "1")
  end

  it "renders one pending status, delivery metrics, read-only links, and no footer" do
    hotel.update!(status: "pending_review")
    submitted_snapshot = snapshot.deep_merge("property" => { "city" => "Semporna" })
    submission = create(:onboarding_submission, hotel:, submitted_by: user, snapshot: submitted_snapshot)
    create(:onboarding_delivery, onboarding_submission: submission, delivery_type: "staff_invitation", status: "sent")
    create(:onboarding_delivery, onboarding_submission: submission, delivery_type: "admin_submitted", status: "sent")

    get_review

    document = response.parsed_body
    expect(document.css(".panel-alert[role='status']").size).to eq(1)
    expect(document.css(".panel-alert[role='status']").text).to include("Awaiting WAStays review", "Submitted by Platform Admin")
    expect(response.body).not_to include("Setup submitted for review")
    expect(response.body).to include("Semporna, Malaysia · MYR")
    expect(document.css("article.panel-metric-card").map { |card| card.text.squish })
      .to include(match(/Sent\s+1\s+Invitations/), match(/Failed\s+0\s+Invitations/))
    expect(document.css("a").any? { |link| link.text.strip == "View" }).to be(true)
    expect(document.at_css("a[href='#{hotel_dashboard_path(hotel)}']").text.squish).to eq("Open PMS")
    expect(document.at_css("footer[data-slot='setup-actions']")).to be_nil
    expect(document.at_css("#onboarding-submission-form")).to be_nil
  end

  it "sends the review page to the dashboard once the property is live" do
    hotel.update!(status: "live")
    create(
      :onboarding_submission, hotel:, submitted_by: user, status: "approved", snapshot:,
      reviewed_by: user, reviewed_at: Time.current
    )

    get_review

    expect(response).to redirect_to(hotel_dashboard_path(hotel))
  end

  it "sends every other onboarding section to the dashboard once the property is live" do
    hotel.update!(status: "live")

    get hotel_onboarding_section_path(hotel, section_key: "property_profile")

    expect(response).to redirect_to(hotel_dashboard_path(hotel))
  end

  it "sends the onboarding entry point to the dashboard once the property is live" do
    hotel.update!(status: "live")

    get hotel_onboarding_path(hotel)

    expect(response).to redirect_to(hotel_dashboard_path(hotel))
  end

  it "still lets the property be edited while it is back in setup" do
    hotel.update!(status: "setup")

    get hotel_onboarding_section_path(hotel, section_key: "property_profile")

    expect(response).to have_http_status(:ok)
  end
end
