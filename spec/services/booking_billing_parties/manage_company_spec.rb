# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingBillingParties::ManageCompany do
  it "idempotently adds a company party with separate booking terms and an audit entry" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    account = create(:hotel_corporate_account, hotel: booking.hotel, direct_bill_enabled: true)

    2.times do
      result = described_class.call(booking: booking, actor: actor, attributes: {
        hotel_corporate_account_id: account.id, settlement_type: "city_ledger", purchase_order_reference: "PO-42"
      })
      expect(result).to be_success
    end

    party = booking.booking_billing_parties.companies.sole
    expect(party.billing_terms).to have_attributes(settlement_type: "city_ledger", purchase_order_reference: "PO-42")
    expect(booking.booking_billing_parties.companies.count).to eq(1)
    expect(BookingAuditLog.where(auditable: booking, action_type: "billing_party_added").count).to eq(2)
  end

  it "rejects an account from another hotel" do
    booking = create(:booking)
    result = described_class.call(booking: booking, actor: create(:user), attributes: {
      hotel_corporate_account_id: create(:hotel_corporate_account).id
    })

    expect(result).not_to be_success
  end
end
