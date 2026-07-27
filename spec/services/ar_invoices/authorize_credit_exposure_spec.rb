# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArInvoices::AuthorizeCreditExposure do
  let(:relationship) { create(:hotel_corporate_account, :direct_bill, credit_limit: 100, credit_currency: "MYR") }
  let(:user) { create(:user, :superadmin) }

  it "allows exposure within the credit limit" do
    result = described_class.call(
      hotel_corporate_account: relationship, pending_amount: 100, pending_currency: "MYR", user: user
    )

    expect(result).to be_success
    expect(result).not_to be_override_used
  end

  it "requires an authorized override with a reason above the credit limit" do
    blocked = described_class.call(
      hotel_corporate_account: relationship, pending_amount: 101, pending_currency: "MYR", user: user
    )
    missing_reason = described_class.call(
      hotel_corporate_account: relationship, pending_amount: 101, pending_currency: "MYR", user: user, override: true
    )
    authorized = described_class.call(
      hotel_corporate_account: relationship, pending_amount: 101, pending_currency: "MYR", user: user,
      override: true, override_reason: "Approved by finance"
    )

    expect(blocked.error).to include("credit limit exceeded")
    expect(missing_reason.error).to include("reason can't be blank")
    expect(authorized).to be_success
    expect(authorized).to be_override_used
    expect(authorized.override_reason).to eq("Approved by finance")
  end

  it "requires an authorized override when currencies cannot be compared" do
    blocked = described_class.call(
      hotel_corporate_account: relationship, pending_amount: 50, pending_currency: "USD", user: user
    )
    authorized = described_class.call(
      hotel_corporate_account: relationship, pending_amount: 50, pending_currency: "USD", user: user,
      override: true, override_reason: "Approved without conversion"
    )

    expect(blocked.error).to include("currencies that cannot be compared")
    expect(authorized).to be_success
  end


  it "does not report an unnecessary submitted override as authorized" do
    result = described_class.call(
      hotel_corporate_account: relationship, pending_amount: 50, pending_currency: "MYR", user: create(:user),
      override: true, override_reason: "Not actually required"
    )

    expect(result).to be_success
    expect(result).not_to be_override_used
    expect(result.override_reason).to be_nil
  end
end
