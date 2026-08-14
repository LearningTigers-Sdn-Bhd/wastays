# frozen_string_literal: true

require "rails_helper"

RSpec.describe Onboarding::RequestTrainingReset do
  include ActiveJob::TestHelper

  let(:account) { create(:account, status: "pending_review") }
  let(:hotel) { create(:hotel, account:, status: "ready_to_launch", training_started_at: 1.day.ago) }
  let(:actor) { create(:user, account:) }

  before do
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    allow(Rails.error).to receive(:report)
  end

  after { clear_enqueued_jobs }

  it "queues one reset and records who requested it" do
    result = nil

    expect {
      result = described_class.call(hotel:, actor:)
    }.to change(OnboardingAuditEvent.where(event_type: "training_reset_requested"), :count).by(1)
      .and have_enqueued_job(Onboarding::ResetTrainingDataJob).with(hotel.id, actor.id)

    expect(result).to be_success
    expect(result.already_queued).to be(false)
    expect(hotel.reload.training_reset_state).to eq("queued")
    expect(OnboardingAuditEvent.last.user).to eq(actor)
  end

  it "is idempotent while the reset is queued" do
    hotel.update!(training_reset_state: "queued")

    expect {
      @result = described_class.call(hotel:, actor:)
    }.not_to have_enqueued_job(Onboarding::ResetTrainingDataJob)

    expect(@result).to be_success
    expect(@result.already_queued).to be(true)
  end

  it "records retries after a rolled-back failure" do
    hotel.update!(training_reset_state: "failed")

    expect {
      described_class.call(hotel:, actor:)
    }.to change(OnboardingAuditEvent.where(event_type: "training_reset_retried"), :count).by(1)
      .and have_enqueued_job(Onboarding::ResetTrainingDataJob).with(hotel.id, actor.id)

    expect(hotel.reload.training_reset_state).to eq("queued")
  end

  it "makes an enqueue failure retryable" do
    allow(Onboarding::ResetTrainingDataJob).to receive(:perform_later).and_return(false)

    result = described_class.call(hotel:, actor:)

    expect(result).not_to be_success
    expect(hotel.reload.training_reset_state).to eq("failed")
    expect(OnboardingAuditEvent.where(hotel:, event_type: "training_reset_failed")).to exist
    expect(Rails.error).to have_received(:report).with(instance_of(RuntimeError), hash_including(handled: true))
  end

  it "rejects a hotel that is not awaiting launch" do
    hotel.update!(status: "pending_review")

    result = described_class.call(hotel:, actor:)

    expect(result).not_to be_success
    expect(result.error).to include("not awaiting")
    expect(enqueued_jobs).to be_empty
  end
end
