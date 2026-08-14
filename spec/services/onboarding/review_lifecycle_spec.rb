require "rails_helper"

RSpec.describe "Onboarding review lifecycle" do
  let(:hotel) { create(:hotel, status: "setup") }
  let(:actor) { create(:user, account: hotel.account) }
  let(:ready) { Onboarding::Readiness::Result.new(ready: true, blocking_issues: [], warnings: []) }
  let(:rates_coverage) { instance_double(Rates::SetupCoverage::Result) }
  let(:snapshot) do
    Onboarding::SubmissionSnapshot::Result.new(
      data: { "version" => 1, "sections" => {} },
      digest: Digest::SHA256.hexdigest("stable")
    )
  end

  before do
    owner_role = create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel Owner")
    create(:user_hotel_access, hotel:, user: actor, role: owner_role)
    Onboarding::InitializeProgress.new(hotel:).call
    hotel.onboarding_sections.update_all(state: "complete", completed_at: Time.current, decision_metadata: {})
    allow(Rates::SetupCoverage).to receive(:call).with(hotel:).and_return(rates_coverage)
    allow(Onboarding::Readiness).to receive(:new).with(hotel:).and_return(instance_double(Onboarding::Readiness, call: ready))
    allow(Onboarding::Readiness).to receive(:new).with(hotel:, rates_coverage:).and_return(instance_double(Onboarding::Readiness, call: ready))
    allow(Onboarding::SubmissionSnapshot).to receive(:call).with(hotel:).and_return(snapshot)
    allow(Onboarding::SubmissionSnapshot).to receive(:call).with(hotel:, rates_coverage:).and_return(snapshot)
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
    expect(hotel.training_started_at).to be_present
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
    allow(Onboarding::SubmissionSnapshot).to receive(:call).with(hotel:, rates_coverage:).and_return(
      Onboarding::SubmissionSnapshot::Result.new(data: {}, digest: Digest::SHA256.hexdigest("changed"))
    )

    result = Onboarding::ApproveOnboarding.call(hotel:, actor: create(:user, :superadmin))

    expect(result).not_to be_success
    expect(result.error).to include("changed after submission")
    expect(hotel.reload.status).to eq("pending_review")
    expect(submission.reload.status).to eq("pending_review")
  end

  it "approves into the launch decision state without activating the account" do
    hotel.account.update!(status: "pending_review")
    submission = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt").submission
    reviewer = create(:user, :superadmin)

    result = Onboarding::ApproveOnboarding.call(hotel:, actor: reviewer)

    expect(result).to be_success
    expect(hotel.reload.status).to eq("ready_to_launch")
    expect(hotel.account.reload.status).to eq("pending_review")
    expect(submission.reload).to have_attributes(status: "approved", reviewed_by: reviewer, snapshot: snapshot.data)
    expect(hotel.onboarding_audit_events.where(event_type: "approved")).to exist
    expect(submission.deliveries.pluck(:delivery_type)).to contain_exactly("owner_launch_decision_required")
  end


  it "keeps training activity and launches exactly once" do
    hotel.account.update!(status: "pending_review")
    submission = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt").submission
    Onboarding::ApproveOnboarding.call(hotel:, actor: create(:user, :superadmin))

    first = Onboarding::CompleteTraining.call(hotel:, actor:, decision: "keep")
    repeated = Onboarding::CompleteTraining.call(hotel:, actor:, decision: "keep")

    expect(first).to be_success
    expect(repeated).to be_success
    expect(hotel.reload).to have_attributes(
      status: "live", training_data_decision: "keep", training_completed_by: actor,
      training_completed_at: be_present, training_reset_state: nil
    )
    expect(hotel.account.reload.status).to eq("active")
    expect(hotel.onboarding_audit_events.where(event_type: "training_keep_selected").count).to eq(1)
    expect(hotel.onboarding_audit_events.where(event_type: "launched").count).to eq(1)
    expect(Onboarding::DispatchPendingDeliveriesJob).to have_received(:perform_later).with(submission.id).exactly(3).times
  end


  it "rejects a conflicting launch decision after launch" do
    submission = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt").submission
    Onboarding::ApproveOnboarding.call(hotel:, actor: create(:user, :superadmin))
    Onboarding::CompleteTraining.call(hotel:, actor:, decision: "keep")

    result = Onboarding::CompleteTraining.call(hotel:, actor:, decision: "reset")

    expect(result).not_to be_success
    expect(result.error).to include("different launch decision")
    expect(hotel.reload).to have_attributes(status: "live", training_data_decision: "keep")
    expect(submission.reload.status).to eq("approved")
  end


  it "finalizes reset only after cleanup has claimed the reset" do
    submission = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt").submission
    Onboarding::ApproveOnboarding.call(hotel:, actor: create(:user, :superadmin))

    premature = Onboarding::CompleteTraining.call(hotel:, actor:, decision: "reset")
    hotel.update!(training_reset_state: "processing")
    completed = Onboarding::CompleteTraining.call(hotel:, actor:, decision: "reset")

    expect(premature).not_to be_success
    expect(completed).to be_success
    expect(hotel.reload).to have_attributes(
      status: "live", training_data_decision: "reset", training_reset_state: nil,
      training_completed_by: actor, training_completed_at: be_present
    )
    expect(hotel.onboarding_audit_events.where(event_type: "training_reset_completed")).to exist
    expect(submission.reload.deliveries.where(delivery_type: "owner_approved")).to exist
  end


  it "leaves the property awaiting launch when readiness changes after approval" do
    Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt")
    Onboarding::ApproveOnboarding.call(hotel:, actor: create(:user, :superadmin))
    not_ready = Onboarding::Readiness::Result.new(ready: false, blocking_issues: [], warnings: [])
    allow(Onboarding::Readiness).to receive(:new).with(hotel:, rates_coverage:)
      .and_return(instance_double(Onboarding::Readiness, call: not_ready))

    result = Onboarding::CompleteTraining.call(hotel:, actor:, decision: "keep")

    expect(result).not_to be_success
    expect(result.error).to include("no longer ready")
    expect(hotel.reload).to have_attributes(status: "ready_to_launch", training_data_decision: nil)
  end


  it "leaves the property awaiting launch when approved configuration changes" do
    hotel.account.update!(status: "pending_review")
    Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt")
    Onboarding::ApproveOnboarding.call(hotel:, actor: create(:user, :superadmin))
    allow(Onboarding::SubmissionSnapshot).to receive(:call).with(hotel:, rates_coverage:).and_return(
      Onboarding::SubmissionSnapshot::Result.new(data: {}, digest: Digest::SHA256.hexdigest("changed-after-approval"))
    )

    result = Onboarding::CompleteTraining.call(hotel:, actor:, decision: "keep")

    expect(result).not_to be_success
    expect(result.error).to include("changed after approval")
    expect(hotel.reload).to have_attributes(status: "ready_to_launch", training_data_decision: nil)
    expect(hotel.account.reload.status).not_to eq("active")
  end

  describe "when the property has invitations waiting" do
    let(:role) { create(:role, account: hotel.account, slug: "front_desk", name: "Front Desk") }
    let!(:staff_draft) { create(:onboarding_staff_draft, hotel:, role:, email: "front@hotel.test") }
    let!(:corporate_draft) { create(:onboarding_corporate_draft, hotel:, email: "billing@acme.test") }

    def invitation_deliveries(submission)
      submission.deliveries.where(delivery_type: %w[staff_invitation corporate_invitation])
    end

    it "tells nobody outside the property at submission" do
      create(:user, :superadmin)

      submission = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt").submission

      expect(invitation_deliveries(submission)).to be_empty
      expect(submission.deliveries.pluck(:delivery_type).uniq).to eq([ "admin_submitted" ])
    end

    it "creates the invitations only once the property is launched" do
      submission = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt").submission

      Onboarding::ApproveOnboarding.call(hotel:, actor: create(:user, :superadmin))

      expect(invitation_deliveries(submission)).to be_empty

      Onboarding::CompleteTraining.call(hotel:, actor:, decision: "keep")

      expect(invitation_deliveries(submission).pluck(:delivery_type, :source_id)).to contain_exactly(
        [ "staff_invitation", staff_draft.id ],
        [ "corporate_invitation", corporate_draft.id ]
      )
    end

    it "leaves no invitations behind when the reviewer requests changes instead" do
      submission = Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "owner-attempt").submission

      Onboarding::RequestChanges.call(
        hotel:, actor: create(:user, :superadmin), section_keys: %w[rooms], explanation: "Fix the rooms."
      )

      expect(invitation_deliveries(submission)).to be_empty
    end
  end
end
