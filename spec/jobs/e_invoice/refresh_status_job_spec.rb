require "rails_helper"

RSpec.describe EInvoice::RefreshStatusJob, type: :job do
  include ActiveJob::TestHelper

  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, booking_quote: nil) }

  it "polls status and re-enqueues while the submission is still refreshable" do
    submission = create(:e_invoice_submission,
      hotel: hotel,
      booking: booking,
      status: "submitted",
      uuid: "uuid-123")

    allow(EInvoice::RefreshStatus).to receive(:call).and_return(success: true, submission: submission)

    expect {
      described_class.perform_now(submission.id, 1)
    }.to have_enqueued_job(described_class).with(submission.id, 2)

    expect(EInvoice::RefreshStatus).to have_received(:call).with(submission)
  end

  it "stops polling when the submission reaches a final state" do
    submission = create(:e_invoice_submission,
      hotel: hotel,
      booking: booking,
      status: "submitted",
      uuid: "uuid-123")
    submission.status = "valid"

    allow(EInvoice::RefreshStatus).to receive(:call).and_return(success: true, submission: submission)

    expect {
      described_class.perform_now(submission.id, 1)
    }.not_to have_enqueued_job(described_class)
  end
end
