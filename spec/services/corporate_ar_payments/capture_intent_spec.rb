# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateArPayments::CaptureIntent do
  let(:intent) { create(:corporate_ar_payment_intent, amount: 150, currency: "MYR", gateway_order_id: "order_ar_1", remittance_suggestions: [ { ar_invoice_id: 1, invoice_number: "1", suggested_amount: "150.00" } ]) }
  let(:verification) do
    {
      status: "captured",
      external_reference: "pay_ar_1",
      gateway_order_id: "order_ar_1",
      payment_method: "card",
      amount: 15000,
      currency: "MYR",
      metadata: { payment_context: "corporate_ar", corporate_ar_payment_intent_id: intent.id }
    }
  end

  it "creates exactly one unapplied AR payment for duplicate captures" do
    expect do
      2.times do
        described_class.call(intent: intent, gateway: "razorpay", verification_result: verification, event_source: "spec")
      end
    end.to change(ArPayment, :count).by(1)
      .and change(PaymentTransaction, :count).by(1)

    payment = intent.reload.ar_payment
    expect(payment).to be_present
    expect(payment.allocation_status).to eq("unapplied")
    expect(payment.metadata["source"]).to eq("corporate_portal_gateway")
  end

  it "still captures when relationship was suspended after gateway capture" do
    intent.hotel_corporate_account.update!(status: "suspended", suspended_at: Time.current)

    result = described_class.call(intent: intent, gateway: "razorpay", verification_result: verification, event_source: "spec")

    expect(result).to be_success
    expect(intent.reload.ar_payment).to be_present
  end
end
