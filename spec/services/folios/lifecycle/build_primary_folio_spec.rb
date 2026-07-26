# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Lifecycle::BuildPrimaryFolio do
  let(:booking) { create(:booking, check_in: Date.current) }
  let(:hotel) { booking.hotel }
  let(:user) { create(:user, account: hotel.account) }

  it "inserts the booking's primary guest folio" do
    folio = described_class.call(booking: booking, actor: user)

    expect(folio).to be_persisted
    expect(folio).to have_attributes(
      hotel: hotel,
      booking: booking,
      folio_sequence: 1,
      is_primary: true,
      status: "open",
      label: nil,
      folio_type: "guest",
      payer_type: "guest",
      created_by: user
    )
    expect(folio.currency).to eq(booking.currency.presence || hotel.default_currency)
    expect(folio.opened_at).to be_present
  end

  it "assigns the booking's folio account reference from the new folio number" do
    folio = described_class.call(booking: booking, actor: user)

    expect(booking.reload.folio_account_reference).to be_present
    expect(folio.folio_number).to be_present
  end

  it "routes the folio to the agent when the booking is linked to an active agent account" do
    hotel_corporate_account = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent")
    booking.update!(hotel_corporate_account: hotel_corporate_account)

    folio = described_class.call(booking: booking, actor: user)

    expect(folio).to have_attributes(
      label: nil,
      folio_type: "external",
      payer_type: "company",
      hotel_corporate_account: hotel_corporate_account
    )
    party = folio.booking_billing_party
    expect(party).to be_present
    expect(party.party_kind).to eq("company")
    expect(booking.booking_billing_parties).to eq([ party ])
  end

  it "reuses the booking's existing billing party for the agent account" do
    hotel_corporate_account = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent")
    booking.update!(hotel_corporate_account: hotel_corporate_account)
    party = booking.booking_billing_parties.create!(
      hotel: hotel,
      hotel_corporate_account: hotel_corporate_account,
      party_kind: "company",
      account_type: hotel_corporate_account.account_type
    )

    expect {
      folio = described_class.call(booking: booking, actor: user)
      expect(folio.booking_billing_party).to eq(party)
    }.not_to change(BookingBillingParty, :count)
  end

  it "falls back to a guest folio when the linked agent account is suspended" do
    hotel_corporate_account = create(:hotel_corporate_account, hotel: hotel, account_type: "travel_agent", status: "suspended")
    booking.update!(hotel_corporate_account: hotel_corporate_account)

    folio = described_class.call(booking: booking, actor: user)

    expect(folio.folio_type).to eq("guest")
    expect(folio.payer_type).to eq("guest")
    expect(booking.booking_billing_parties).to be_empty
  end

  it "raises instead of recovering when a primary folio already exists" do
    create(:booking_folio, hotel: hotel, booking: booking)

    expect {
      described_class.call(booking: booking, actor: user)
    }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
