# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateArPayments::ProcessWebhook do
  it "delegates to capture intent" do
    intent = instance_double("CorporateArPaymentIntent", id: 1, gateway: "razorpay", gateway_order_id: "order_ar_1")

    expect(CorporateArPayments::CaptureIntent).to receive(:call).with(
      intent: intent,
      gateway: "razorpay",
      payment_response: { razorpay_payment_id: "pay_ar_1", razorpay_order_id: "order_ar_1" },
      verification_result: { status: "captured", external_reference: "pay_ar_1", gateway_order_id: "order_ar_1" },
      event_source: "corporate_ar_webhook"
    )

    described_class.call(
      intent: intent,
      gateway: "razorpay",
      processed_payload: { status: "captured", external_reference: "pay_ar_1", gateway_order_id: "order_ar_1" },
      webhook_payload: {}
    )
  end
end
