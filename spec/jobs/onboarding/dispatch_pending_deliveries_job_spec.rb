require "rails_helper"

RSpec.describe Onboarding::DispatchPendingDeliveriesJob, type: :job do
  it "recovers a delivery left processing by a stopped worker" do
    delivery = create(:onboarding_delivery, status: "processing", updated_at: 20.minutes.ago)
    allow(Onboarding::DeliverJob).to receive(:perform_later)

    described_class.perform_now

    expect(delivery.reload).to have_attributes(
      status: "failed", error_message: "Delivery worker stopped before completion"
    )
    expect(Onboarding::DeliverJob).to have_received(:perform_later).with(delivery.id)
  end
end
