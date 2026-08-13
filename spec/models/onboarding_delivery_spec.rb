require "rails_helper"

RSpec.describe OnboardingDelivery, type: :model do
  it "requires a globally unique idempotency key" do
    delivery = create(:onboarding_delivery)
    duplicate = build(:onboarding_delivery, idempotency_key: delivery.idempotency_key)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:idempotency_key]).to include("has already been taken")
  end

  it "records failures without completing the delivery" do
    delivery = create(:onboarding_delivery)

    delivery.fail!("provider unavailable")

    expect(delivery).to have_attributes(status: "failed", error_message: "provider unavailable", completed_at: nil)
  end
end
