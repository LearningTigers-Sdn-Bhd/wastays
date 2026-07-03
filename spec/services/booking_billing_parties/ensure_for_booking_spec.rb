# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingBillingParties::EnsureForBooking do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel) }

  it "creates one guest billing party for every booking guest" do
    first_guest = create(:booking_guest, booking: booking)
    second_guest = create(:booking_guest, booking: booking)

    result = described_class.call(booking: booking)

    expect(result.map(&:booking_guest)).to contain_exactly(first_guest, second_guest)
    expect(result.map(&:party_kind)).to all(eq("guest"))
  end

  it "is idempotent" do
    create(:booking_guest, booking: booking)

    expect { 2.times { described_class.call(booking: booking) } }.not_to change(BookingBillingParty, :count)
  end

  it "reactivates an archived automatic guest party" do
    booking_guest = create(:booking_guest, booking: booking)
    party = booking_guest.booking_billing_party
    party.update!(archived_at: 1.day.ago)

    result = described_class.call(booking: booking)

    expect(result).to contain_exactly(party.reload)
    expect(party.archived_at).to be_nil
  end

  it "creates company parties from existing company folios and links those folios" do
    account = create(:hotel_corporate_account, hotel: hotel)
    folio = create(:booking_folio, :secondary, booking: booking, hotel: hotel, hotel_corporate_account: account)

    described_class.call(booking: booking)

    party = booking.booking_billing_parties.companies.sole
    expect(party.hotel_corporate_account).to eq(account)
    expect(folio.reload.booking_billing_party).to eq(party)
  end

  it "links legacy guest folios only when the booking has one guest party" do
    booking_guest = create(:booking_guest, booking: booking)
    folio = create(:booking_folio, booking: booking, hotel: hotel, payer_type: "guest")

    described_class.call(booking: booking)

    expect(folio.reload.booking_billing_party.booking_guest).to eq(booking_guest)
  end

  it "does not link legacy guest folios when guest ownership is ambiguous" do
    create(:booking_guest, booking: booking)
    create(:booking_guest, booking: booking)
    folio = create(:booking_folio, booking: booking, hotel: hotel, payer_type: "guest")

    described_class.call(booking: booking)

    expect(folio.reload.booking_billing_party).to be_nil
  end

  it "does not create billing parties for agent, hotel, or custom folios" do
    create(:booking_folio, :secondary, booking: booking, hotel: hotel, payer_type: "agent", hotel_corporate_account: nil)
    create(:booking_folio, :secondary, booking: booking, hotel: hotel, payer_type: "custom", hotel_corporate_account: nil)

    described_class.call(booking: booking)

    expect(booking.booking_billing_parties).to be_empty
  end
end
