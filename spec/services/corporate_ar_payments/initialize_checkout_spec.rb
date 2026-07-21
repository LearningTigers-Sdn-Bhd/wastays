# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateArPayments::InitializeCheckout do
  let(:hotel) { create(:hotel, status: "approved") }
  let(:relationship) { create(:hotel_corporate_account, :direct_bill, hotel: hotel, status: "active") }
  let(:intent) { create(:corporate_ar_payment_intent, hotel: hotel, hotel_corporate_account: relationship, amount: 150, currency: "MYR", gateway: "razorpay") }

  before do
    create(:payment_setting, settable: hotel, gateway: "razorpay")
  end

  it "rejects expired intents" do
    intent.update!(expires_at: 1.second.ago)
    intent.reload
    result = described_class.call(intent: intent, callback_url: "https://example.com/callback")
    expect(result).not_to be_success
    expect(result.error).to eq("Payment request has expired.")
  end

  it "rejects non-razorpay gateways" do
    intent.update!(gateway: "stripe")
    result = described_class.call(intent: intent, callback_url: "https://example.com/callback")
    expect(result).not_to be_success
    expect(result.error).to eq("Only Razorpay is available for corporate AR payments.")
  end
end
