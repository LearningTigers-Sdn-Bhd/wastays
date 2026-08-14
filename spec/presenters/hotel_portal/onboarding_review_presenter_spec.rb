# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::OnboardingReviewPresenter do
  let(:hotel) { create(:hotel, status: "setup", city: "Kota Belud", country: "Malaysia", default_currency: "MYR") }
  let(:user) { create(:user, account: hotel.account, name: "Platform Admin") }
  let(:ready) { Onboarding::Readiness::Result.new(ready: true, blocking_issues: [], warnings: warnings) }
  let(:warnings) do
    [ Onboarding::Readiness::Finding.new(
      section_key: "staff_setup", severity: :warning, code: :deferred,
      message: "Nothing was added in this optional section."
    ) ]
  end
  let(:snapshot) do
    {
      "property" => { "city" => "Kota Belud", "country" => "Malaysia", "default_currency" => "MYR" },
      "sections" => Onboarding::SectionCatalog.keys.index_with do |key|
        { "state" => key == "staff_setup" ? "skipped" : "complete" }
      end,
      "staff" => [ { "name" => "Ari", "send_invitation" => true } ],
      "taxes" => [],
      "room_revenue" => { "tax_rule_keys" => [ "sst" ] },
      "rooms" => [ { "name" => "Garden Room", "quantity" => 4 }, { "name" => "Suite", "quantity" => 2 } ],
      "rates" => { "coverage" => { "end_date" => "2027-08-12" }, "plans" => [ { "name" => "Standard" } ] },
      "commercial" => {
        "extra_charges" => [], "discounts" => [ { "name" => "Early bird" } ],
        "payment_methods" => [ { "name" => "Cash" } ],
        "corporate_accounts" => [ { "company_name" => "Acme", "send_invitation" => false } ]
      },
      "ota_handover" => []
    }
  end

  before do
    Onboarding::InitializeProgress.new(hotel:).call
    hotel.onboarding_sections.update_all(state: "complete", completed_at: Time.current)
    hotel.onboarding_sections.find_by!(section_key: "staff_setup").update!(state: "skipped")
  end

  def presenter(readiness: ready, submission: nil)
    navigation = Onboarding::NavigationState.new(hotel:).call
    described_class.new(hotel:, navigation:, readiness:, submission:, snapshot:)
  end

  it "summarizes ready setup in four compact metrics and grouped rows" do
    review = presenter

    expect(review).to have_attributes(
      title: "Review & submit",
      status_title: "Ready to submit",
      submit_label: "Submit for review"
    )
    expect(review.metrics.map { |metric| [ metric.label, metric.value, metric.detail ] }).to eq([
      [ "Required setup", "8 of 8", "Complete" ],
      [ "Optional decisions", "5 of 5", "1 deferred" ],
      [ "Needs attention", "0", "No sections" ],
      [ "Invitations", "2", "1 send · 1 hold" ]
    ])
    expect(review.groups.map(&:label)).to eq([ "Property", "Team", "Finance", "Rooms & rates", "Commercial" ])

    rows = review.groups.flat_map(&:rows).index_by { |row| row.entry.definition.key }
    expect(rows.fetch("property_profile").summary).to eq("Kota Belud, Malaysia · MYR")
    expect(rows.fetch("staff_setup")).to have_attributes(summary: "1 staff member", status_label: "Deferred")
    expect(rows.fetch("rooms").summary).to eq("2 room types · 6 rooms")
    expect(rows.fetch("rates_availability").summary).to eq("Coverage through 12 Aug 2027")
    expect(rows.fetch("channel_manager").summary).to eq("No channel handover")
  end

  it "puts requested changes first and uses Fix only on affected rows" do
    hotel.onboarding_sections.find_by!(section_key: "rooms").update!(state: "needs_attention")
    hotel.onboarding_sections.find_by!(section_key: "review").update!(state: "needs_attention")
    finding = Onboarding::Readiness::Finding.new(
      section_key: "rooms", severity: :blocking, code: :needs_attention,
      message: "Review the requested changes in this section."
    )
    readiness = Onboarding::Readiness::Result.new(ready: false, blocking_issues: [ finding ], warnings:)
    submission = create(
      :onboarding_submission, hotel:, submitted_by: user, status: "changes_requested",
      reviewed_by: user, reviewed_at: Time.current, review_explanation: "Correct the room capacity."
    )

    review = presenter(readiness:, submission:)
    rooms = review.groups.flat_map(&:rows).find { |row| row.entry.definition.key == "rooms" }
    property = review.groups.flat_map(&:rows).find { |row| row.entry.definition.key == "property_profile" }

    expect(review).to have_attributes(
      title: "Changes requested",
      status_description: "Correct the room capacity.",
      submit_label: "Submit changes for review"
    )
    expect(review.metrics.first).to have_attributes(label: "Needs attention", value: "1")
    expect(rooms).to have_attributes(status_label: "Needs attention", action_label: "Fix")
    expect(property.action_label).to eq("View")
  end

  it "uses only invitation deliveries for post-submission metrics" do
    hotel.update!(status: "pending_review")
    submission = create(:onboarding_submission, hotel:, submitted_by: user, snapshot:)
    create(:onboarding_delivery, onboarding_submission: submission, delivery_type: "staff_invitation", status: "sent")
    create(:onboarding_delivery, onboarding_submission: submission, delivery_type: "corporate_invitation", status: "held")
    create(:onboarding_delivery, onboarding_submission: submission, delivery_type: "staff_invitation", status: "processing")
    create(:onboarding_delivery, onboarding_submission: submission, delivery_type: "corporate_invitation", status: "failed")
    create(:onboarding_delivery, onboarding_submission: submission, delivery_type: "admin_submitted", status: "sent")
    submission.deliveries.load

    review = presenter(submission:)

    expect(review).to have_attributes(title: "Setup submitted", status_title: "Awaiting WAStays review")
    expect(review.metrics.map { |metric| [ metric.label, metric.value ] }).to eq([
      [ "Sent", "1" ], [ "Held", "1" ], [ "Pending", "1" ], [ "Failed", "1" ]
    ])
    expect(review.groups.flat_map(&:rows).map(&:action_label).uniq).to eq([ "View" ])
  end

  it "uses approved wording for a live property" do
    hotel.update!(status: "live")
    submission = create(
      :onboarding_submission, hotel:, submitted_by: user, status: "approved", snapshot:,
      reviewed_by: user, reviewed_at: Time.current
    )

    review = presenter(submission:)

    expect(review).to have_attributes(title: "Setup approved", status_title: "Property is live")
    expect(review.status_description).to include("Approved by Platform Admin", "This property is live")
    expect(review.status_description).not_to include("review")
  end
end
