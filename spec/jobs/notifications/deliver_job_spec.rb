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
end
