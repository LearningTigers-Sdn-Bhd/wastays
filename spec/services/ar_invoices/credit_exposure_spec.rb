# frozen_string_literal: true

require "rails_helper"

RSpec.describe ArInvoices::CreditExposure do
  it "does not warn below 90 percent of the credit limit" do
    relationship = create(:hotel_corporate_account, credit_limit: 1000, direct_bill_enabled: true)
    create_invoice(relationship: relationship, amount: 700)

    result = described_class.call(hotel_corporate_account: relationship, pending_amount: 199)

    expect(result.warning_state).to eq("none")
    expect(result.warning?).to eq(false)
    expect(result.projected_exposure).to eq(899.to_d)
  end

  it "warns at 90 percent of the credit limit without blocking" do
    relationship = create(:hotel_corporate_account, credit_limit: 1000, direct_bill_enabled: true)
    create_invoice(relationship: relationship, amount: 800)

    result = described_class.call(hotel_corporate_account: relationship, pending_amount: 100)

    expect(result.warning_state).to eq("near_limit")
    expect(result.warning_message).to include("90% of credit limit")
    expect(result.warning_message).to include("Direct Bill is still allowed")
  end

  it "warns when projected exposure exceeds the credit limit" do
    relationship = create(:hotel_corporate_account, credit_limit: 1000, direct_bill_enabled: true)
    create_invoice(relationship: relationship, amount: 900)

    result = described_class.call(hotel_corporate_account: relationship, pending_amount: 101)

    expect(result.warning_state).to eq("over_limit")
    expect(result.warning_message).to include("exceeds credit limit")
    expect(result.warning_message).to include("Direct Bill is still allowed")
  end

  it "warns when no credit limit is set" do
    relationship = create(:hotel_corporate_account, credit_limit: nil, direct_bill_enabled: true)

    result = described_class.call(hotel_corporate_account: relationship, pending_amount: 100)

    expect(result.warning_state).to eq("no_limit")
    expect(result.warning_message).to include("No credit limit is set")
  end

  def create_invoice(relationship:, amount:)
    booking = create(:booking, hotel: relationship.hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: relationship.hotel, hotel_corporate_account: relationship)
    create(:ar_invoice, hotel: relationship.hotel, booking_folio: folio, hotel_corporate_account: relationship, amount: amount, outstanding_amount: amount)
  end
end
