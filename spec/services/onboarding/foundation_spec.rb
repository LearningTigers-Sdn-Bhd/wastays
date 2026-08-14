require "rails_helper"

RSpec.describe "Onboarding foundation" do
  let(:hotel) { create(:hotel, status: "setup") }

  it "initializes the stable ordered journey idempotently" do
    expect {
      Onboarding::InitializeProgress.new(hotel: hotel).call
    }.to change(HotelOnboardingSection, :count).by(14)
      .and change(OnboardingAuditEvent, :count).by(1)

    expect {
      Onboarding::InitializeProgress.new(hotel: hotel).call
    }.not_to change(HotelOnboardingSection, :count)

    expect(hotel.onboarding_sections.in_journey_order.pluck(:section_key)).to eq(Onboarding::SectionCatalog.keys)
  end

  it "enforces prerequisites and records completion audit events" do
    blocked = Onboarding::UpdateSection.new(
      hotel: hotel,
      section_key: "roles_permissions",
      state: "complete"
    ).call
    expect(blocked.success?).to be(false)

    result = Onboarding::UpdateSection.new(
      hotel: hotel,
      section_key: "property_profile",
      state: "complete",
      metadata: { source: "spec" }
    ).call

    expect(result.success?).to be(true)
    expect(result.section).to have_attributes(state: "complete", completed_at: be_present)
    expect(hotel.onboarding_audit_events.last).to have_attributes(
      event_type: "completed",
      section_key: "property_profile",
      metadata: { "source" => "spec" }
    )
  end

  it "does not allow required sections to be skipped" do
    result = Onboarding::UpdateSection.new(
      hotel: hotel,
      section_key: "property_profile",
      state: "skipped"
    ).call

    expect(result.success?).to be(false)
    expect(result.error).to include("cannot be skipped")
  end

  it "resolves the first unmet section and reports readiness findings" do
    Onboarding::InitializeProgress.new(hotel: hotel).call

    expect(Onboarding::ResumePageResolver.new(hotel: hotel).call.key).to eq("property_profile")

    readiness = Onboarding::Readiness.new(hotel: hotel).call
    expect(readiness.ready).to be(false)
    expect(readiness.blocking_issues.map(&:section_key)).to include("property_profile", "staff_setup")
  end

  it "does not count shell placeholder completion as launch-ready" do
    Onboarding::InitializeProgress.new(hotel: hotel).call
    hotel.onboarding_sections.update_all(
      state: "complete",
      completed_at: Time.current,
      decision_metadata: { placeholder: true }
    )

    readiness = Onboarding::Readiness.new(hotel: hotel).call

    expect(readiness.ready).to be(false)
    expect(readiness.blocking_issues.map(&:section_key)).to include("property_profile")
    expect(readiness.blocking_issues.map(&:section_key)).not_to include("review")
  end

  it "rejects lifecycle submission until onboarding is ready" do
    result = Onboarding::TransitionLifecycle.new(hotel: hotel, to: "pending_review").call

    expect(result.success?).to be(false)
    expect(result.error).to include("not ready")
    expect(hotel.reload.status).to eq("setup")
  end

  it "submits a ready setup hotel and records the lifecycle event" do
    Onboarding::InitializeProgress.new(hotel: hotel).call
    hotel.onboarding_sections.update_all(state: "complete", completed_at: Time.current)
    allow(Onboarding::Readiness).to receive(:new).with(hotel: hotel)
      .and_return(instance_double(Onboarding::Readiness, call: Onboarding::Readiness::Result.new(ready: true, blocking_issues: [], warnings: [])))

    result = Onboarding::TransitionLifecycle.new(hotel: hotel, to: "pending_review").call

    expect(result.success?).to be(true)
    expect(hotel.reload.status).to eq("pending_review")
    expect(hotel.onboarding_audit_events.last.event_type).to eq("submitted")
  end
end
