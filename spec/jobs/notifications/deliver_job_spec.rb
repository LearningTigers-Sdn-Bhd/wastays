require "rails_helper"

RSpec.describe Notifications::DeliverJob, type: :job do
  let(:delivery) { create(:notification_delivery, channel: "email", status: "pending") }

  it "marks sent deliveries with sent_at" do
    adapter = instance_double(Notifications::Channels::Email, call: true)
    allow(Notifications::Channels::Email).to receive(:new).with(delivery: delivery).and_return(adapter)

    described_class.perform_now(delivery.id)

    expect(delivery.reload.status).to eq("sent")
    expect(delivery.sent_at).to be_present
  end

  it "marks the delivery failed and stores the error message" do
    delivery = create(:notification_delivery, channel: "whatsapp", status: "pending")
    adapter = instance_double(Notifications::Channels::WhatsappWebhook)

    allow(Notifications::Channels::WhatsappWebhook).to receive(:new).with(delivery: delivery).and_return(adapter)
    allow(adapter).to receive(:call).and_raise(StandardError, "timeout")

    expect {
      described_class.perform_now(delivery.id)
    }.to raise_error(StandardError, "timeout")

    expect(delivery.reload.status).to eq("failed")
    expect(delivery.error_message).to eq("timeout")
    expect(delivery.failed_at).to be_present
  end

  it "skips stale delayed jobs when schedule has changed" do
    scheduled_delivery = create(
      :notification_delivery,
      channel: "email",
      status: "pending",
      payload: { "scheduled_for" => 2.hours.from_now.iso8601, "guest_name" => "Aisha" }
    )

    expect(Notifications::Channels::Email).not_to receive(:new)

    described_class.perform_now(scheduled_delivery.id, 1.hour.from_now.iso8601)

    expect(scheduled_delivery.reload.status).to eq("pending")
    expect(scheduled_delivery.sent_at).to be_nil
  end
end
