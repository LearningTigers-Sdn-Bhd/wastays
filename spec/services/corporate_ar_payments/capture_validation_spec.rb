# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateArPayments::CaptureIntent do
  let(:intent) { create(:corporate_ar_payment_intent, amount: 150, currency: "MYR", gateway_order_id: "order_ar_1") }

  it "rejects captured payments with a mismatched amount" do
    result = described_class.call(
      intent: intent,
      gateway: "razorpay",
      verification_result: {
        status: "captured",
        external_reference: "pay_wrong_amount",
        gateway_order_id: "order_ar_1",
        payment_method: "card",
        amount: 10000,
        currency: "MYR"
      },
      event_source: "spec"
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Payment amount does not match this AR payment request.")
    expect(intent.reload.ar_payment).to be_nil
    expect(intent).to be_failed
  end

  it "rejects captured payments with a mismatched order" do
    result = described_class.call(
      intent: intent,
      gateway: "razorpay",
      verification_result: {
        status: "captured",
        external_reference: "pay_wrong_order",
        gateway_order_id: "order_other",
        payment_method: "card",
        amount: 15000,
        currency: "MYR"
      },
      event_source: "spec"
    )

    expect(result).not_to be_success
    expect(result.error).to eq("Payment order does not match this AR payment request.")
    expect(intent.reload.ar_payment).to be_nil
  end
end
