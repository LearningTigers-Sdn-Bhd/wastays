# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArPaymentSubmissions::Reject do
  let(:hotel) { create(:hotel, status: "live") }
  let(:reviewer) { create(:user) }
  let(:corporate_user) { create(:user, :corporate) }
  let(:relationship) do
    create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account, account_type: "travel_agent")
  end
  let(:booking) do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, corporate_booked_by: corporate_user,
                     status: "confirmed", payment_status: "pending",
                     check_in: 10.days.from_now, check_out: 12.days.from_now,
                     payment_due_at: 6.hours.from_now)
  end
  let(:submission) do
    create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: booking, status: "pending")
  end

  def reject(reason: "The amount did not match the booking total")
    described_class.call(submission: submission, reason: reason, reviewed_by: reviewer)
  end

  it "rejects the submission with its reason" do
    expect(reject).to be_success
    expect(submission.reload).to have_attributes(status: "rejected", reviewed_by_id: reviewer.id)
  end

  # This is the notification that matters most in the payment path: an agent who
  # is not told will find out when the rooms are gone.
  it "tells the agent why, and what happens next" do
    reject

    delivery = NotificationDelivery.find_by(booking: booking, notification_type: "agent_payment_rejected")
    expect(delivery).to have_attributes(status: "pending")
    expect(delivery.payload["rejection_reason"]).to include("did not match")
  end

  # reject! extends payment_due_at by the time the review took. Quoting the old
  # deadline would be worse than quoting none.
  it "quotes the extended deadline, not the one the slip was sent against" do
    original_due_at = booking.payment_due_at
    submission # sent now, so the review below genuinely takes two hours
    travel_to(2.hours.from_now) { reject }

    expect(booking.reload.payment_due_at).to be > original_due_at
    delivery = NotificationDelivery.find_by(booking: booking, notification_type: "agent_payment_rejected")
    expect(Time.zone.parse(delivery.payload["payment_due_at"])).to be_within(1.second).of(booking.payment_due_at)
  end

  it "reports the failure rather than notifying when a reason is missing" do
    result = reject(reason: nil)

    expect(result).not_to be_success
    expect(result.error).to be_present
    expect(NotificationDelivery.where(notification_type: "agent_payment_rejected")).to be_empty
  end

  it "sends nothing for a submission that settles invoices rather than a booking" do
    invoice_submission = create(:ar_payment_submission, hotel: hotel, hotel_corporate_account: relationship, booking: nil)

    described_class.call(submission: invoice_submission, reason: "Wrong account", reviewed_by: reviewer)

    expect(NotificationDelivery.where(notification_type: "agent_payment_rejected")).to be_empty
  end
end
