# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArPaymentSubmissions::Approve do
  let(:hotel) { create(:hotel, status: "live") }
  let(:reviewer) { create(:user) }
  let(:corporate_user) { create(:user, :corporate) }
  let(:relationship) do
    create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account, account_type: "travel_agent")
  end
  let(:booking) do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, corporate_booked_by: corporate_user,
                     status: "confirmed", payment_status: "pending", payment_due_at: 6.hours.from_now)
  end
  let(:submission) do
    create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking, status: "pending")
  end
  let(:ar_payment) { create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship) }

  it "approves the submission and clears the deadline it was sent against" do
    result = described_class.call(submission: submission, ar_payment: ar_payment, reviewed_by: reviewer)

    expect(result).to be_success
    expect(submission.reload).to have_attributes(status: "approved", reviewed_by_id: reviewer.id)
    expect(booking.reload.payment_due_at).to be_nil
  end

  it "tells the agent their payment landed" do
    described_class.call(submission: submission, ar_payment: ar_payment, reviewed_by: reviewer)

    delivery = NotificationDelivery.find_by(booking: booking, notification_type: "agent_payment_approved")
    expect(delivery).to have_attributes(status: "pending")
    expect(delivery.payload["reference_number"]).to eq(submission.reference_number)
  end

  # An invoice settlement is ordinary AR with nobody waiting on an answer about
  # rooms, so it is not chased through this path.
  it "sends nothing for a submission that settles invoices rather than a booking" do
    invoice_submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: nil)

    described_class.call(submission: invoice_submission, ar_payment: ar_payment, reviewed_by: reviewer)

    expect(NotificationDelivery.where(notification_type: "agent_payment_approved")).to be_empty
  end

  # The money is recorded either way; a mail server being down is not a reason
  # to leave a slip sitting unreviewed.
  it "still approves when notifying fails" do
    allow(Notifications::QueueAgentPaymentNotice).to receive(:call).and_raise(StandardError, "smtp down")

    result = described_class.call(submission: submission, ar_payment: ar_payment, reviewed_by: reviewer)

    expect(result).to be_success
    expect(submission.reload.status).to eq("approved")
  end
end
