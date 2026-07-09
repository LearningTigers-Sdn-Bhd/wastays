# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingBillingTerms, type: :model do
  it "allows City Ledger for an active Direct Bill company party" do
    account = create(:hotel_corporate_account, direct_bill_enabled: true)
    party = create(:booking_billing_party, hotel: account.hotel, booking: create(:booking, hotel: account.hotel), hotel_corporate_account: account)

    terms = described_class.new(booking_billing_party: party, settlement_type: "city_ledger", purchase_order_reference: "PO-1")

    expect(terms).to be_valid
  end

  it "rejects City Ledger for guests and ineligible company accounts" do
    guest_party = create(:booking_guest).booking_billing_party
    company_party = create(:booking_billing_party)

    expect(described_class.new(booking_billing_party: guest_party, settlement_type: "city_ledger", purchase_order_reference: "PO-1")).not_to be_valid
    expect(described_class.new(booking_billing_party: company_party, settlement_type: "city_ledger", purchase_order_reference: "PO-1")).not_to be_valid
  end

  it "requires a purchase order reference for City Ledger settlement" do
    account = create(:hotel_corporate_account, direct_bill_enabled: true)
    party = create(:booking_billing_party, hotel: account.hotel, booking: create(:booking, hotel: account.hotel), hotel_corporate_account: account)

    terms = described_class.new(booking_billing_party: party, settlement_type: "city_ledger")

    expect(terms).not_to be_valid
    expect(terms.errors[:purchase_order_reference]).to be_present
  end
end
