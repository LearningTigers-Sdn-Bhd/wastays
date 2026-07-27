# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingBillingParties::UpdateGroupTerms do
  it "updates existing matching account parties without creating missing parties" do
    group = create(:group_booking)
    booking_one = create(:booking, hotel: group.hotel, group_booking: group, group_position: 1)
    booking_two = create(:booking, hotel: group.hotel, group_booking: group, group_position: 2)
    booking_without_party = create(:booking, hotel: group.hotel, group_booking: group, group_position: 3)
    account = create(:hotel_corporate_account, hotel: group.hotel)
    parties = [ booking_one, booking_two ].map do |booking|
      create(:booking_billing_party, booking:, hotel: group.hotel, hotel_corporate_account: account, party_kind: "company")
    end
    actor = create(:user, account: group.hotel.account)

    result = described_class.call(party: parties.first, actor:, attributes: { settlement_type: "cash_bank", authorization_reference: "AUTH-GROUP" })

    expect(result).to be_success
    expect(parties.map { |party| party.billing_terms.reload.authorization_reference }).to all(eq("AUTH-GROUP"))
    expect(booking_without_party.booking_billing_parties).to be_empty
  end

  it "rejects guest payers" do
    party = create(:booking_guest).booking_billing_party

    result = described_class.call(party:, actor: create(:user), attributes: { settlement_type: "cash_bank" })

    expect(result).not_to be_success
    expect(result.errors).to include("Only account payers can be updated across a group.")
  end
end
