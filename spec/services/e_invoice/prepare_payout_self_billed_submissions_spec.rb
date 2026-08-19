require "rails_helper"

RSpec.describe EInvoice::PreparePayoutSelfBilledSubmissions, type: :service do
  let(:hotel) { create(:hotel) }
  let!(:setting) { create(:e_invoice_setting, :intermediary_ready, hotel: hotel) }
  let(:batch) { create(:payout_batch, hotel: hotel) }
  let!(:wastays_booking) do
    create(:booking,
      hotel: hotel,
      booking_quote: create(:booking_quote, hotel: hotel, token: nil),
      status: "completed",
      fund_collector: "wastays",
      net_amount: 100.0,
      payout_batch: batch)
  end
  let!(:hotel_booking) do
    create(:booking,
      :direct_hotel_payment,
      hotel: hotel,
      booking_quote: create(:booking_quote, hotel: hotel, token: nil),
      status: "completed",
      net_amount: 50.0,
      payout_batch: batch)
  end

  it "creates submission only for wastays-collected payout booking" do
    ActiveJob::Base.queue_adapter = :test

    expect {
      described_class.call(batch)
    }.to change(EInvoiceSubmission.payout_self_billed, :count).by(1)

    submission = wastays_booking.reload.payout_self_billed_submission
    expect(submission).to have_attributes(
      payout_batch: batch,
      document_type: "11",
      document_scenario: "payout_self_billed_invoice",
      submission_mode: "taxpayer",
      fund_collector: "wastays"
    )
    expect(hotel_booking.reload.payout_self_billed_submission).to be_nil
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs.last[:args]).to eq([ submission.id ])
  end

  it "does not create duplicate submissions when called again" do
    ActiveJob::Base.queue_adapter = :test

    described_class.call(batch) # First call creates submission

    expect {
      described_class.call(batch) # Second call should not create new submission
    }.not_to change(EInvoiceSubmission.payout_self_billed, :count)
  end
end
