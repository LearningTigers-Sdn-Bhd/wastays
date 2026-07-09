# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingBillingParty, type: :model do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }

  it "allows a guest party for a booking guest on the same booking" do
    booking_guest = create(:booking_guest, booking: booking)

    party = booking_guest.booking_billing_party

    expect(party).to be_valid
  end

  it "automatically creates a guest billing party when a guest is added to a booking" do
    booking_guest = create(:booking_guest, booking: booking)

    expect(booking_guest.booking_billing_party).to have_attributes(booking: booking, hotel: hotel, party_kind: "guest")
  end

  it "rejects a guest party from another booking" do
    other_booking_guest = create(:booking_guest)

    party = described_class.new(hotel: hotel, booking: booking, party_kind: "guest", booking_guest: other_booking_guest)

    expect(party).not_to be_valid
    expect(party.errors[:booking_guest]).to include("must belong to the same booking")
  end

  it "allows a company party for a hotel corporate account from the same hotel" do
    account = create(:hotel_corporate_account, hotel: hotel)

    party = described_class.new(hotel: hotel, booking: booking, party_kind: "company", hotel_corporate_account: account)

    expect(party).to be_valid
  end

  it "rejects a company party from another hotel" do
    account = create(:hotel_corporate_account)

    party = described_class.new(hotel: hotel, booking: booking, party_kind: "company", hotel_corporate_account: account)

    expect(party).not_to be_valid
    expect(party.errors[:hotel_corporate_account]).to include("must belong to the same hotel")
  end

  it "requires exactly one billing identity" do
    party = described_class.new(hotel: hotel, booking: booking, party_kind: "guest")

    expect(party).not_to be_valid
    expect(party.errors[:base]).to include("must reference exactly one billing identity")
  end

  it "rejects mismatched identity for party kind" do
    account = create(:hotel_corporate_account, hotel: hotel)

    party = described_class.new(hotel: hotel, booking: booking, party_kind: "guest", hotel_corporate_account: account)

    expect(party).not_to be_valid
    expect(party.errors[:booking_guest]).to include("must be present for guest billing parties")
  end

  it "allows one billing party to own multiple folios" do
    party = create(:booking_guest, booking: booking).booking_billing_party

    first = create(:booking_folio, booking: booking, hotel: hotel, booking_billing_party: party)
    second = create(:booking_folio, booking: booking, hotel: hotel, booking_billing_party: party, is_primary: false, name: "Incidentals Folio")

    expect(party.booking_folios).to contain_exactly(first, second)
  end

  it "rejects a folio billing party from another booking" do
    party = create(:booking_guest).booking_billing_party
    folio = build(:booking_folio, booking: booking, hotel: hotel, booking_billing_party: party)

    expect(folio).not_to be_valid
    expect(folio.errors[:booking_billing_party]).to include("must belong to the same booking")
  end

  it "rejects a folio whose payer type does not match the billing party kind" do
    party = create(:booking_guest, booking: booking).booking_billing_party
    folio = build(:booking_folio, :secondary, booking: booking, hotel: hotel, booking_billing_party: party)

    expect(folio).not_to be_valid
    expect(folio.errors[:booking_billing_party]).to include("must match guest payer type")
  end

  it "rejects a company folio whose account does not match the billing party" do
    party = create(:booking_billing_party, :company, booking: booking, hotel: hotel)
    other_account = create(:hotel_corporate_account, hotel: hotel)
    folio = build(:booking_folio, :secondary, booking: booking, hotel: hotel, booking_billing_party: party, hotel_corporate_account: other_account)

    expect(folio).not_to be_valid
    expect(folio.errors[:booking_billing_party]).to include("must match the selected company account")
  end
end
