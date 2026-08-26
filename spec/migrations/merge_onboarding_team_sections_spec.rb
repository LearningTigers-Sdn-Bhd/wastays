# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260826100000_merge_onboarding_team_sections")

RSpec.describe MergeOnboardingTeamSections do
  let(:hotel) { create(:hotel, status: "setup") }

  # The catalog no longer holds the old keys, so the rows have to be written
  # around the model's validation, the same way a live database already holds
  # them.
  def seed_legacy(roles:, staff:)
    described_class::Section.where(hotel_id: hotel.id, section_key: %w[team_setup roles_permissions staff_setup]).delete_all
    described_class::Section.create!({ hotel_id: hotel.id, section_key: "roles_permissions" }.merge(roles))
    described_class::Section.create!({ hotel_id: hotel.id, section_key: "staff_setup" }.merge(staff))
  end

  # The audit table validates nothing, but the association's model does.
  def legacy_audit_event(section_key)
    described_class::AuditEvent.create!(
      hotel_id: hotel.id, event_type: "completed", section_key: section_key,
      occurred_at: Time.current, metadata: {}
    )
  end

  def merged = described_class::Section.find_by(hotel_id: hotel.id, section_key: "team_setup")

  before { Onboarding::InitializeProgress.new(hotel: hotel).call }

  it "merges a finished pair into one complete row that keeps the fingerprint" do
    seed_legacy(
      roles: { state: "complete", completed_at: 2.days.ago,
               decision_metadata: { confirmed_role_slugs: Onboarding::RolePresets::PRESET_SLUGS, permission_fingerprint: "abc123" } },
      staff: { state: "complete", completed_at: 1.day.ago,
               decision_metadata: { source: "staff_draft_setup", staff_count: 2 } }
    )

    described_class.new.up

    expect(merged).to have_attributes(state: "complete")
    expect(merged.decision_metadata).to include(
      "source" => "team_setup",
      "permission_fingerprint" => "abc123",
      "staff_count" => 2
    )
    expect(described_class::Section.where(hotel_id: hotel.id, section_key: %w[roles_permissions staff_setup])).to be_empty
  end

  # "No additional staff" was a skip on an optional step. The merged step is
  # required, so the same decision has to read as complete instead.
  it "turns a skipped staff half into a completed decision" do
    seed_legacy(
      roles: { state: "complete", decision_metadata: { permission_fingerprint: "abc123" } },
      staff: { state: "skipped", skipped_at: 1.day.ago,
               decision_metadata: { source: "staff_draft_setup", decision: "no_additional_staff", staff_count: 0 } }
    )

    described_class.new.up

    expect(merged).to have_attributes(state: "complete", skipped_at: nil)
    expect(merged.decision_metadata).to include("decision" => "no_additional_staff", "source" => "team_setup")
  end

  it "keeps a half that needs attention blocking, and carries an unfinished pair as in progress" do
    seed_legacy(
      roles: { state: "complete", decision_metadata: { permission_fingerprint: "abc123" } },
      staff: { state: "needs_attention" }
    )
    described_class.new.up
    expect(merged.state).to eq("needs_attention")

    seed_legacy(roles: { state: "complete" }, staff: { state: "not_started" })
    described_class.new.up
    expect(merged.state).to eq("in_progress")
  end

  it "moves the audit trail of both halves onto the merged key" do
    seed_legacy(roles: { state: "complete" }, staff: { state: "complete" })
    legacy_audit_event("roles_permissions")
    legacy_audit_event("staff_setup")

    described_class.new.up

    expect(hotel.onboarding_audit_events.where(section_key: "team_setup").count).to eq(2)
    expect(hotel.onboarding_audit_events.where(section_key: %w[roles_permissions staff_setup])).to be_empty
  end
end
