require "rails_helper"

RSpec.describe EInvoice::SubmitJob, type: :job do
  include ActiveJob::TestHelper

  it "enqueues background status refresh after a successful submitted result" do
    submission = create(:e_invoice_submission, status: "pending")
    submitted_submission = submission.tap do |record|
      allow(record).to receive(:refreshable?).and_return(true)
    end

    allow(EInvoice::Submit).to receive(:call).with(submission).and_return(success: true, submission: submitted_submission)

    expect {
      described_class.perform_now(submission.id)
    }.to have_enqueued_job(EInvoice::RefreshStatusJob).with(submission.id)
  end

  it "does not enqueue refresh when submission fails" do
    submission = create(:e_invoice_submission, status: "pending")

    allow(EInvoice::Submit).to receive(:call).with(submission).and_return(success: false, submission: submission)

    expect {
      described_class.perform_now(submission.id)
    }.not_to have_enqueued_job(EInvoice::RefreshStatusJob)
  end
end
