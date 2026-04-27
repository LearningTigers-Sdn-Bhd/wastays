# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::ProcessVerification do
  let(:hotel) { create(:hotel) }
  let(:quote) { create(:booking_quote, hotel: hotel, total_amount: 100) }
  let(:gateway) { "razorpay" }
  let(:payment_response) { { razorpay_payment_id: "pay_1", razorpay_order_id: "ord_1" } }
  let(:guest_details) { { name: "John Doe", email: "john@example.com" } }

  let(:setting) { double("PaymentSetting") }
  let(:adapter) { instance_double(Payments::GatewayAdapters::Razorpay) }

  subject { described_class.new(quote: quote, gateway: gateway, payment_response: payment_response, guest_details: guest_details) }

  before do
    allow(quote.hotel).to receive(:effective_payment_setting).with(gateway).and_return(setting)
    allow(Payments::GatewayRegistry).to receive(:fetch).with(gateway: gateway, setting: setting).and_return(adapter)
  end

  context "when payment is captured" do
    let(:verification_result) do
      { status: "captured", external_reference: "pay_1", metadata: { guest_name: "John Doe" } }
    end

    before do
      allow(adapter).to receive(:verify_client_callback).and_return(verification_result)
    end

    it "confirms the booking and records the transaction" do
      booking = build(:booking, id: 1)
      confirm_result = OpenStruct.new(success?: true, booking: booking)

      expect_any_instance_of(BookingEngine::ConfirmBooking).to receive(:call).and_return(confirm_result)
      expect(Payments::TransactionRecorder).to receive(:record_verification).with(
        hash_including(booking: booking, verification_result: verification_result)
      )

      result = subject.call
      expect(result.success?).to be true
      expect(result.booking).to eq(booking)
    end

    it "returns failure if booking confirmation fails" do
      confirm_result = OpenStruct.new(success?: false, message: "Room no longer available")

      expect_any_instance_of(BookingEngine::ConfirmBooking).to receive(:call).and_return(confirm_result)

      result = subject.call
      expect(result.success?).to be false
      expect(result.error).to eq("Room no longer available")
    end

    it "returns failure if guest details are missing" do
      # Case where no guest details in params and none in metadata
      service = described_class.new(quote: quote, gateway: gateway, payment_response: payment_response, guest_details: {})
      allow(adapter).to receive(:verify_client_callback).and_return(verification_result.merge(metadata: {}))

      result = service.call
      expect(result.success?).to be false
      expect(result.error).to eq("Missing guest details for booking confirmation.")
    end
  end

  context "when payment fails" do
    let(:verification_result) { { status: "failed", message: "Declined by bank" } }

    before do
      allow(adapter).to receive(:verify_client_callback).and_return(verification_result)
    end

    it "records the failed transaction and returns failure" do
      expect(Payments::TransactionRecorder).to receive(:record_verification).with(
        hash_including(verification_result: verification_result)
      )

      result = subject.call
      expect(result.success?).to be false
      expect(result.error).to eq("Declined by bank")
    end
  end

  it "handles unsupported gateway errors" do
    allow(Payments::GatewayRegistry).to receive(:fetch).and_raise(Payments::GatewayRegistry::UnsupportedGatewayError, "Unsupported")

    result = subject.call
    expect(result.success?).to be false
    expect(result.error).to eq("Unsupported")
  end
end
