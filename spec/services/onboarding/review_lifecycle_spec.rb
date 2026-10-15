require "rails_helper"

RSpec.describe "Onboarding review lifecycle" do
  let(:hotel) { create(:hotel, status: "setup") }
  let(:actor) { create(:user, account: hotel.account) }
  let(:ready) { Onboarding::Readiness::Result.new(ready: true, blocking_issues: [], warnings: []) }
  let(:rates_coverage) { instance_double(Rates::SetupCoverage::Result) }
  let(:snapshot) do
    Onboarding::SubmissionSnapshot::Result.new(
      data: { "version" => 1, "sections" => {}, "rates" => { "coverage" => { "start_date" => Date.current.to_s, "end_date" => (Date.current + 364.days).to_s } } },
      digest: Digest::SHA256.hexdigest("stable")
    )
  end

  before do
    owner_role = create(:role, account: hotel.account, slug: "hotel_owner", name: "Hotel Owner")
    create(:user_hotel_access, hotel:, user: actor, role: owner_role)
    Onboarding::InitializeProgress.new(hotel:).call
    hotel.onboarding_sections.update_all(state: "complete", completed_at: Time.current, decision_metadata: {})
    allow(Rates::SetupCoverage).to receive(:call).with(hotel:).and_return(rates_coverage)
    allow(Rates::SetupCoverage).to receive(:call).with(hotel:, start_date: anything, end_date: anything).and_return(rates_coverage)
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

RSpec.describe "Onboarding review across days" do
  let(:hotel) { create(:hotel, status: "setup", preferred_channel_manager: "channex") }
  let(:actor) { create(:user, account: hotel.account) }
  let(:reviewer) { create(:user, :superadmin) }
  let(:room) { create(:room_type, hotel:, quantity: 3, base_price: 120) }
  let(:upload_photos) { true }
  let(:submitted_end) { Date.new(2027, 9, 19) }
  let(:submission) { Onboarding::SubmitOnboarding.call(hotel:, actor:, idempotency_key: "dated-review").submission }

  around do |example|
    travel_to(Time.zone.local(2026, 9, 20, 12)) { example.run }
  end

  before do
    room
    roles = Onboarding::RolePresets::PRESET_SLUGS.map do |slug|
      hotel.account.roles.find_by(slug:) || create(:role, account: hotel.account, slug:)
    end
    create(:user_hotel_access, hotel:, user: actor, role: roles.first)
    if upload_photos
      hotel.photos.attach(io: File.open(Rails.root.join("spec/fixtures/files/sample_image.jpg")), filename: "property.jpg", content_type: "image/jpeg")
      hotel.update!(featured_photo_attachment_id: hotel.photos.attachments.sole.id)
    end
    create(:hotel_transaction_configuration, hotel:) unless hotel.hotel_transaction_configuration
    create(:hotel_payment_method, hotel:)
    Onboarding::InitializeProgress.new(hotel:).call
    hotel.onboarding_sections.update_all(state: "complete", completed_at: Time.current, decision_metadata: {})
    hotel.onboarding_sections.find_by!(section_key: "team_setup").update!(decision_metadata: {
      source: "team_setup", permission_fingerprint: Onboarding::RolePresets.permission_fingerprint(roles)
    })
    hotel.onboarding_sections.find_by!(section_key: "taxes_fees").update!(decision_metadata: {
      confirmed: true, custom_tax_count: hotel.hotel_taxes.count
    })
    hotel.onboarding_sections.find_by!(section_key: "room_revenue").update!(decision_metadata: {
      tax_fingerprint: Onboarding::TaxFingerprint.call(hotel)
    })
    { extra_charges: "extra_charge_setup", discounts: "discount_setup", corporate_accounts: "corporate_account_setup", channel_manager: "channel_manager_setup" }.each do |key, source|
      hotel.onboarding_sections.find_by!(section_key: key).update!(decision_metadata: { source: })
    end
    RoomInventory.insert_all!((Date.current..submitted_end).map do |date|
      { room_type_id: room.id, date:, quantity: 2, status: "open", available_room_numbers: [] }
    end)
    allow(Onboarding::DispatchPendingDeliveriesJob).to receive(:perform_later)
    allow(ChannelManagers::SyncJob).to receive(:perform_later)
    unless upload_photos
      expect(Onboarding::SavePropertyPhotos.new(hotel:, actor:, complete: true).call).to be_success
    end
    expect(Onboarding::Readiness.new(hotel:).call).to have_attributes(ready: true)
    expect(submission).to be_present
  end

  context "without property photos" do
    let(:upload_photos) { false }

    it "submits, approves, and launches with the no-photos decision" do
      expect(hotel.photos).not_to be_attached
      expect(hotel.status).to eq("pending_review")
      expect(submission.snapshot.dig("property", "photo_count")).to eq(0)
      original = submission.snapshot.deep_dup

      expect(Onboarding::ApproveOnboarding.call(hotel:, actor: reviewer)).to be_success
      expect(Onboarding::CompleteTraining.call(hotel:, actor:, decision: "keep")).to be_success

      expect(hotel.reload.status).to eq("live")
      expect(hotel.onboarding_sections.find_by!(section_key: "property_photos").state).to eq("skipped")
      expect(submission.reload.snapshot).to eq(original)
      expect(Onboarding::Readiness.new(hotel:).call.warnings)
        .to include(have_attributes(section_key: "property_photos", code: :deferred))
    end
  end

  it "approves yesterday's submission and preserves submitted evidence" do
    original = submission.attributes.slice("snapshot", "configuration_digest", "readiness_snapshot")
    sections = hotel.onboarding_sections.order(:id).pluck(:id, :decision_metadata)
    travel 1.day

    result = Onboarding::ApproveOnboarding.call(hotel:, actor: reviewer)

    expect(result).to be_success
    expect(hotel.reload.status).to eq("ready_to_launch")
    expect(room.room_inventories.count).to eq(366)
    expect(room.room_inventories.find_by!(date: submitted_end + 1.day)).to have_attributes(quantity: 2, status: "open")
    expect(room.room_rates).to be_empty
    expect(submission.reload.attributes.slice(*original.keys)).to eq(original)
    expect(hotel.onboarding_sections.order(:id).pluck(:id, :decision_metadata)).to eq(sections)
    expect { Onboarding::ApproveOnboarding.call(hotel:, actor: reviewer) }.not_to change(RoomInventory, :count)
  end

  %w[keep reset].each do |decision|
    it "extends availability for a later #{decision} launch" do
      travel 3.days
      expect(Onboarding::ApproveOnboarding.call(hotel:, actor: reviewer)).to be_success
      travel 2.days
      if decision == "reset"
        hotel.update!(training_reset_state: "queued")
        result = Onboarding::ResetOperationalData.call(hotel:, actor:)
      else
        result = Onboarding::CompleteTraining.call(hotel:, actor:, decision:)
      end

      expect(result).to be_success
      expect(hotel.reload).to have_attributes(status: "live", training_data_decision: decision)
      expect(room.room_inventories.count).to eq(370)
      expect(Rates::SetupCoverage.call(hotel:).complete?).to be(true)
      expect { Onboarding::CompleteTraining.call(hotel:, actor:, decision:) }.not_to change(RoomInventory, :count)
    end
  end

  it "rejects actual setup changes before appending availability" do
    travel 1.day
    hotel.update!(name: "Changed after submission")
    expect {
      result = Onboarding::ApproveOnboarding.call(hotel:, actor: reviewer)
      expect(result.error).to include("changed after submission")
    }.not_to change(RoomInventory, :count)
  end

  it "rejects gaps inside the original window without repairing them" do
    room.room_inventories.find_by!(date: Date.current + 5.days).destroy!
    travel 1.day
    expect {
      expect(Onboarding::ApproveOnboarding.call(hotel:, actor: reviewer)).not_to be_success
    }.not_to change(RoomInventory, :count)
    expect(hotel.inventory_audit_logs.reload).to be_empty
  end

  it "rolls availability back when the final approval transition fails" do
    travel 1.day
    transition = instance_double(Onboarding::TransitionLifecycle, call: Onboarding::TransitionLifecycle::Result.failure("Transition failed"))
    allow(Onboarding::TransitionLifecycle).to receive(:new).and_return(transition)

    expect {
      expect(Onboarding::ApproveOnboarding.call(hotel:, actor: reviewer).error).to eq("Transition failed")
    }.not_to change(RoomInventory, :count)

    expect(hotel.inventory_audit_logs.reload).to be_empty
    expect(hotel.reload.status).to eq("pending_review")
    expect(submission.reload.status).to eq("pending_review")
    expect(ChannelManagers::SyncJob).not_to have_received(:perform_later)
  end

  it "rolls appended records and audit back when readiness fails" do
    travel 2.days
    RoomInventory.insert_all!([
      { room_type_id: room.id, date: submitted_end + 1.day, quantity: 0, status: "open", available_room_numbers: [] }
    ])

    expect {
      result = Onboarding::ApproveOnboarding.call(hotel:, actor: reviewer)
      expect(result.error).to include("no longer ready")
    }.not_to change(RoomInventory, :count)
    expect(hotel.inventory_audit_logs.reload).to be_empty
    expect(hotel.reload.status).to eq("pending_review")
    expect(ChannelManagers::SyncJob).not_to have_received(:perform_later)
  end
end
