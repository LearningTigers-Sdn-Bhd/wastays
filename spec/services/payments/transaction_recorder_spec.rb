require "rails_helper"

RSpec.describe Payments::TransactionRecorder do
  describe ".record_checkout_session" do
    let(:quote) { create(:booking_quote) }

    it "creates checkout_initiated transaction" do
      tx = described_class.record_checkout_session(
        quote: quote,
        gateway: "razorpay",
        checkout_payload: {
          order_id: "order_1",
          amount: 12000,
          currency: "MYR"
        }
      )

      expect(tx.gateway).to eq("razorpay")
      expect(tx.gateway_order_id).to eq("order_1")
      expect(tx.status).to eq("checkout_initiated")
      expect(tx.amount_subunits).to eq(12000)
      expect(tx.currency).to eq("MYR")
      expect(tx.event_source).to eq("checkout_session")
    end

    it "upserts existing transaction by gateway_order_id" do
      existing = create(:payment_transaction, booking_quote: quote, gateway: "razorpay", gateway_order_id: "order_1", external_reference: nil, status: "pending")

      tx = described_class.record_checkout_session(
        quote: quote,
        gateway: "razorpay",
        checkout_payload: {
          order_id: "order_1",
          amount: 13000,
          currency: "MYR"
        }
      )

      expect(tx.id).to eq(existing.id)
      expect(tx.amount_subunits).to eq(13000)
      expect(tx.status).to eq("checkout_initiated")
    end
  end

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

    it "stores failure message and failed status" do
      result = described_class.record_verification(
        quote: quote,
        gateway: "razorpay",
        payment_response: {
          razorpay_order_id: "order_fail",
          razorpay_signature: "sig_fail"
        },
        verification_result: {
          status: "failed",
          external_reference: "pay_fail",
          message: "Signature mismatch."
        }
      )

      expect(result.status).to eq("failed")
      expect(result.error_message).to eq("Signature mismatch.")
      expect(result.verified_at).to be_present
      expect(result.captured_at).to be_nil
    end

    it "marks booking as wastays-collected when gateway capture is linked to booking" do
      booking = create(:booking, booking_quote: quote, hotel: quote.hotel, fund_collector: "unknown")

      described_class.record_verification(
        quote: quote,
        gateway: "razorpay",
        booking: booking,
        payment_response: {
          razorpay_order_id: "order_stamp",
          razorpay_signature: "sig_stamp"
        },
        verification_result: {
          status: "captured",
          external_reference: "pay_stamp",
          payment_method: "card",
          amount: 5000,
          currency: "MYR",
          metadata: { quote_token: quote.token }
        }
      )

      expect(booking.reload.fund_collector).to eq("wastays")
    end
  end

  describe ".record_webhook" do
    let(:quote) { create(:booking_quote) }

    it "records captured webhook and timestamps capture" do
      result = described_class.record_webhook(
        quote: quote,
        gateway: "razorpay",
        webhook_payload: { event: "payment.captured" },
        processed_payload: {
          external_reference: "pay_webhook_1",
          gateway_order_id: "order_webhook_1",
          status: "captured",
          payment_method: "card",
          amount: 1000,
          currency: "MYR",
          metadata: { source: "webhook" }
        }
      )

      expect(result.status).to eq("captured")
      expect(result.event_source).to eq("webhook")
      expect(result.verified_at).to be_present
      expect(result.captured_at).to be_present
    end

    it "normalizes unknown statuses to pending" do
      result = described_class.record_webhook(
        quote: quote,
        gateway: "razorpay",
        webhook_payload: { event: "unknown" },
        processed_payload: {
          external_reference: "pay_webhook_2",
          gateway_order_id: "order_webhook_2",
          status: "strange_status"
        }
      )

      expect(result.status).to eq("pending")
      expect(result.verified_at).to be_present
      expect(result.captured_at).to be_nil
    end
  end
end
