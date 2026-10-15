# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::QueueAgentPaymentNotice do
  let(:hotel) { create(:hotel, status: "live") }
  let(:corporate_user) { create(:user, :corporate) }
  let(:relationship) do
    create(:hotel_corporate_account, hotel: hotel, corporate_account: corporate_user.account, account_type: "travel_agent")
  end
  let(:booking) do
    create(:booking, hotel: hotel, hotel_corporate_account: relationship, corporate_booked_by: corporate_user,
                     status: "confirmed", payment_status: "pending", payment_due_at: 6.hours.from_now)
  end

  def queue(key: "agent_payment_reminder:1", type: "agent_payment_reminder")
    described_class.call(
      booking: booking,
      notification_type: type,
      trigger_event: "agent_payment_deadline_approaching",
      idempotency_key: key
    )
  end

  it "records the delivery and hands it to the sender" do
    expect { queue }.to have_enqueued_job(Notifications::DeliverJob)

    delivery = NotificationDelivery.find_by(idempotency_key: "agent_payment_reminder:1")
    expect(delivery).to have_attributes(status: "pending", channel: "email", booking_id: booking.id)
  end

  # The whole reason these go through notification_deliveries rather than a
  # mailer call is so an agent asking "was I warned?" gets a row.
  it "sends nothing twice for the same key" do
    queue

    expect { queue }.not_to have_enqueued_job(Notifications::DeliverJob)
    expect(NotificationDelivery.where(idempotency_key: "agent_payment_reminder:1").count).to eq(1)
  end

  it "treats a different key as a different message" do
    queue
    queue(key: "agent_payment_reminder:2")

    expect(NotificationDelivery.count).to eq(2)
  end

  # A genuine validation failure is a bug worth seeing, not a race to swallow.
  it "raises when the save fails for a reason other than the key already existing" do
    allow_any_instance_of(NotificationDelivery).to receive(:save!)
      .and_raise(ActiveRecord::RecordInvalid.new(NotificationDelivery.new))

    expect { queue }.to raise_error(ActiveRecord::RecordInvalid)
  end

  # Nowhere to write is still something that happened, and a silent pass would
  # leave the same dispute unanswerable.
  it "records a skipped delivery rather than passing silently when there is no address" do
    # An account with no contact address and nobody signed up to it: the eZee
    # import creates these by the hundred.
    unreachable = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent", contact_email: nil)
    booking.update!(hotel_corporate_account: unreachable, corporate_booked_by: nil)

    result = queue

    expect(result.sent).to be(false)
    expect(result.delivery).to have_attributes(status: "skipped")
    expect(result.delivery.error_message).to include("no contact email")
  end
end
