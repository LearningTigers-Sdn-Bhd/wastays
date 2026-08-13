require "rails_helper"

RSpec.describe "Onboarding review lifecycle" do
  let(:hotel) { create(:hotel, status: "setup") }
  let(:actor) { create(:user, account: hotel.account) }
  let(:ready) { Onboarding::Readiness::Result.new(ready: true, blocking_issues: [], warnings: []) }
  let(:snapshot) do
    Onboarding::SubmissionSnapshot::Result.new(
      data: { "version" => 1, "sections" => {} },
      digest: Digest::SHA256.hexdigest("stable")
    )
  end

  before do
    Onboarding::InitializeProgress.new(hotel:).call
    hotel.onboarding_sections.update_all(state: "complete", completed_at: Time.current, decision_metadata: {})
    allow(Onboarding::Readiness).to receive(:new).with(hotel:).and_return(instance_double(Onboarding::Readiness, call: ready))
    allow(Onboarding::SubmissionSnapshot).to receive(:call).with(hotel:).and_return(snapshot)
    allow(Onboarding::DispatchPendingDeliveriesJob).to receive(:perform_later)
  end

  it "submits once and returns the same result for repeated keys" do
    first = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt-1")
    repeated = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt-1")
    another_key = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt-2")

    expect(first).to be_success
    expect(repeated.submission).to eq(first.submission)
    expect(another_key.submission).to eq(first.submission)
    expect(hotel.reload.status).to eq("pending_review")
    expect(hotel.onboarding_submissions.count).to eq(1)
    expect(hotel.onboarding_audit_events.where(event_type: "submitted")).to exist
  end

  it "requests targeted changes and preserves the submission history" do
    submission = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt").submission
    reviewer = create(:user, :superadmin)

    result = Onboarding::RequestChanges.call(
      hotel:, actor: reviewer, section_keys: %w[rooms payment_methods], explanation: "Correct these details."
    )

    expect(result).to be_success
    expect(hotel.reload.status).to eq("setup")
    expect(submission.reload).to have_attributes(
      status: "changes_requested", reviewed_by: reviewer, review_explanation: "Correct these details."
    )
    expect(hotel.onboarding_sections.where(section_key: %w[rooms payment_methods review]).pluck(:state).uniq).to eq([ "needs_attention" ])
    expect(hotel.onboarding_audit_events.where(event_type: "changes_requested", section_key: "rooms")).to exist
  end

  it "blocks approval when the current configuration differs" do
    submission = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt").submission
    allow(Onboarding::SubmissionSnapshot).to receive(:call).with(hotel:).and_return(
      Onboarding::SubmissionSnapshot::Result.new(data: {}, digest: Digest::SHA256.hexdigest("changed"))
    )

    result = Onboarding::ApproveOnboarding.call(hotel:, actor: create(:user, :superadmin))

    expect(result).not_to be_success
    expect(result.error).to include("changed after submission")
    expect(hotel.reload.status).to eq("pending_review")
    expect(submission.reload.status).to eq("pending_review")
  end

  it "approves directly to live and retains the approved snapshot" do
    submission = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt").submission
    reviewer = create(:user, :superadmin)

    result = Onboarding::ApproveOnboarding.call(hotel:, actor: reviewer)

    expect(result).to be_success
    expect(hotel.reload.status).to eq("live")
    expect(hotel.account.reload.status).to eq("active")
    expect(submission.reload).to have_attributes(status: "approved", reviewed_by: reviewer, snapshot: snapshot.data)
    expect(hotel.onboarding_audit_events.where(event_type: "approved")).to exist
  end
end
