# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingBillingParties::ManageCompany do
  it "idempotently adds a company party with separate booking terms and an audit entry" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    account = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel)

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

  it "sets account_type from the submitted attribute, defaulting to company" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    account = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel)

    result = described_class.call(booking: booking, actor: actor, attributes: {
      hotel_corporate_account_id: account.id, account_type: "government"
    })
    expect(result.party.account_type).to eq("government")

    default_booking = create(:booking, hotel: booking.hotel)
    default_result = described_class.call(booking: default_booking, actor: actor, attributes: {
      hotel_corporate_account_id: account.id
    })
    expect(default_result.party.account_type).to eq("company")
  end

  it "rejects an account from another hotel" do
    booking = create(:booking)
    result = described_class.call(booking: booking, actor: create(:user), attributes: {
      hotel_corporate_account_id: create(:hotel_corporate_account).id
    })

    expect(result).not_to be_success
  end

  it "creates exactly one folio when a new company party is added" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    account = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel)

    result = described_class.call(booking: booking, actor: actor, attributes: { hotel_corporate_account_id: account.id })

    expect(result).to be_success
    party = result.party
    expect(party.booking_folios.count).to eq(1)
    folio = party.booking_folios.sole
    expect(folio).to have_attributes(payer_type: "company", folio_type: "external", hotel_corporate_account_id: account.id)
  end

  it "does not create a second folio when only billing_terms are updated on an already-active party" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    account = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel)

    described_class.call(booking: booking, actor: actor, attributes: { hotel_corporate_account_id: account.id })
    expect do
      described_class.call(booking: booking, actor: actor, attributes: { hotel_corporate_account_id: account.id, settlement_type: "cash_bank" })
    end.not_to change { BookingFolio.count }
  end

  it "does not duplicate the folio when reactivating an archived party that already has one" do
    booking = create(:booking)
    actor = create(:user, account: booking.hotel.account)
    account = create(:hotel_corporate_account, :direct_bill, hotel: booking.hotel)

    described_class.call(booking: booking, actor: actor, attributes: { hotel_corporate_account_id: account.id })
    party = booking.booking_billing_parties.companies.sole
    party.update!(archived_at: Time.current)

    expect do
      described_class.call(booking: booking, actor: actor, attributes: { hotel_corporate_account_id: account.id })
    end.not_to change { BookingFolio.count }
    expect(party.reload.archived_at).to be_nil
  end

  describe ".call_for_group" do
    it "creates one party and one folio per booking in the group" do
      group = create(:group_booking)
      booking_one = create(:booking, hotel: group.hotel, group_booking: group, group_position: 1)
      booking_two = create(:booking, hotel: group.hotel, group_booking: group, group_position: 2)
      actor = create(:user, account: group.hotel.account)
      account = create(:hotel_corporate_account, :direct_bill, hotel: group.hotel)

      result = described_class.call_for_group(group_booking: group, actor: actor, attributes: { hotel_corporate_account_id: account.id })

      expect(result).to be_success
      [ booking_one, booking_two ].each do |booking|
        party = booking.booking_billing_parties.companies.sole
        expect(party.hotel_corporate_account).to eq(account)
        expect(party.booking_folios.count).to eq(1)
      end
    end

    it "rolls back all bookings if one booking's ManageCompany call fails" do
      group = create(:group_booking)
      booking_one = create(:booking, hotel: group.hotel, group_booking: group, group_position: 1)
      booking_two = create(:booking, hotel: group.hotel, group_booking: group, group_position: 2)
      actor = create(:user, account: group.hotel.account)
      account = create(:hotel_corporate_account, :direct_bill, hotel: group.hotel)

      call_count = 0
      allow(described_class).to receive(:call).and_wrap_original do |original, **kwargs|
        call_count += 1
        call_count == 2 ? OpenStruct.new(success?: false, party: nil, error: "boom") : original.call(**kwargs)
      end

      expect do
        described_class.call_for_group(group_booking: group, actor: actor, attributes: { hotel_corporate_account_id: account.id })
      end.not_to change { BookingBillingParty.count }

      expect(booking_one.booking_billing_parties).to be_empty
      expect(booking_two.booking_billing_parties).to be_empty
    end
  end
end
