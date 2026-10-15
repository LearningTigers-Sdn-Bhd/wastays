require "rails_helper"

RSpec.describe EInvoice::RequestForGuest do
  let(:hotel) { create(:hotel, status: "live") }
  let(:booking) do
    create(:booking,
      hotel: hotel,
      status: "completed",
      payment_status: "captured",
      checked_out_at: Time.current,
      guest_city: "Kota Kinabalu",
      guest_state_code: "12",
      guest_address_country: "Malaysia",
      guest_country: "Malaysia",
      guest_tin: "IG12345678901",
      guest_document_type: "passport"
    )
  end

  def call(subject = booking)
    described_class.new(booking: subject).call
  end

  it "queues the job when everything is ready" do
    allow(booking).to receive(:e_invoice_buyer_details_missing).and_return([])

    expect { call }.to have_enqueued_job(EInvoice::AutoIssueJob)
      .with(booking.id, requested_by_guest: true)
  end

  it "refuses a booking whose payment has not concluded" do
    booking.update_columns(payment_status: "pending")

    result = call(booking.reload)

    expect(result.success?).to be false
    expect(result.error).to include("payment has not concluded")
  end

  it "names the details that are missing" do
    allow(booking).to receive(:e_invoice_buyer_details_missing).and_return([ "city", "state" ])

    result = call

    expect(result.success?).to be false
    expect(result.error).to include("city and state")
  end

  it "refuses when an e-invoice was already issued" do
    allow(booking).to receive(:e_invoice_buyer_details_missing).and_return([])
    allow(booking).to receive(:e_invoice_already_issued?).and_return(true)

    result = call

    expect(result.success?).to be false
    expect(result.error).to include("already been issued")
  end

  it "reports a request that is already queued" do
    allow(booking).to receive(:e_invoice_buyer_details_missing).and_return([])
    allow(booking).to receive(:pending_guest_e_invoice_submission)
      .and_return(build(:e_invoice_submission, hotel: hotel, booking: booking))

    result = call

    expect(result.success?).to be false
    expect(result.already_queued).to be true
    expect(result.error).to include("already being prepared")
  end
end
