# frozen_string_literal: true

require "rails_helper"

RSpec.describe CorporateArPayments::ProcessVerification do
  let(:intent) { create(:corporate_ar_payment_intent, amount: 150, currency: "MYR", gateway_order_id: "order_ar_1") }

  it "requires a configured payment gateway" do
    result = described_class.call(intent: intent, payment_response: {})
    expect(result).not_to be_success
    expect(result.error).to eq("Payment gateway is not configured.")
  end
end
