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
                     status: "confirmed", payment_status: "pending", payment_due_at: 6.hours.from_now,
                     total_amount: 100.0, currency: "MYR")
  end
  let!(:folio) { create(:booking_folio, booking: booking, hotel: hotel, currency: "MYR") }
  let(:submission) do
    create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking,
                                   status: "pending", amount: 100.0, currency: "MYR")
  end
  let(:ar_payment) { create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 100.0) }

  it "approves the submission and clears the deadline it was sent against" do
    result = described_class.call(submission: submission, ar_payment: ar_payment, reviewed_by: reviewer)

    expect(result).to be_success
    expect(submission.reload).to have_attributes(status: "approved", reviewed_by_id: reviewer.id)
    expect(booking.reload.payment_due_at).to be_nil
  end

  # The AR side is only half of it: the desk settles a stay against its folio,
  # not against an unallocated AR credit, so an approval that never reaches the
  # folio would still read as unpaid at checkout.
  it "posts the payment to the booking's folio and marks the booking paid" do
    result = described_class.call(submission: submission, ar_payment: ar_payment, reviewed_by: reviewer)

    expect(result).to be_success
    transaction = folio.folio_transactions.payment.last
    expect(transaction.amount).to eq(100.0)
    expect(transaction.metadata["ar_payment_submission_id"]).to eq(submission.id)
    expect(booking.reload.payment_status).to eq("captured")
  end

  # A slip only ever covers part of what is owed is a real case -- the agent
  # sends a deposit, not the full balance -- and the booking must not read as
  # fully paid because of it.
  it "reads as partially paid when the slip covers less than the total" do
    submission.ar_payment_submission_allocations.destroy_all
    submission.update!(amount: 40.0)
    partial_payment = create(:ar_payment, hotel: hotel, hotel_corporate_account: relationship, amount: 40.0)

    described_class.call(submission: submission, ar_payment: partial_payment, reviewed_by: reviewer)

    expect(booking.reload.payment_status).to eq("partial")
  end

  # A folio has to exist before money can be posted to it; a booking created
  # outside the normal flow without one must refuse cleanly rather than lose
  # the payment silently.
  it "refuses, and leaves the submission pending, when the booking has no folio" do
    folioless_booking = create(:booking, hotel: hotel, hotel_corporate_account: relationship,
                                         status: "confirmed", payment_status: "pending",
                                         payment_due_at: 6.hours.from_now, total_amount: 100.0, currency: "MYR")
    folioless_submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship,
                                                          booking: folioless_booking, status: "pending",
                                                          amount: 100.0, currency: "MYR")

    result = described_class.call(submission: folioless_submission, ar_payment: ar_payment, reviewed_by: reviewer)

    expect(result).not_to be_success
    expect(result.error).to include("no folio")
    expect(folioless_submission.reload.status).to eq("pending")
    expect(folioless_booking.reload.payment_due_at).to be_present
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
