require "rails_helper"

RSpec.describe Payments::TransactionRecorder do
  describe ".record_verification" do
    let(:quote) { create(:booking_quote) }

    it "updates an existing transaction by gateway_order_id when external_reference is first seen on callback" do
      existing = create(
        :payment_transaction,
        booking_quote: quote,
        gateway: "razorpay",
        gateway_order_id: "order_abc",
        external_reference: nil,
        status: "pending"
      )

      result = described_class.record_verification(
        quote: quote,
        gateway: "razorpay",
        payment_response: {
          razorpay_order_id: "order_abc",
          razorpay_payment_id: "pay_abc",
          razorpay_signature: "sig_abc"
        },
        verification_result: {
          status: "captured",
          external_reference: "pay_abc",
          payment_method: "netbanking",
          amount: 5000,
          currency: "MYR",
          metadata: { quote_token: quote.token }
        }
      )

      expect(result.id).to eq(existing.id)
      expect(result.external_reference).to eq("pay_abc")
      expect(result.status).to eq("captured")
      expect(result.payment_method).to eq("netbanking")
      expect(result.signature).to eq("sig_abc")
      expect(result.verified_at).to be_present
      expect(result.captured_at).to be_present
    end
  end
end
