# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Lifecycle::EnsureOtaFolio do
  let(:booking) { create(:booking) }
  let(:source) { create(:booking_source, kind: "ota") }

  it "keeps the normal primary and creates one external OTA folio and room route" do
    folio = described_class.call!(booking:, booking_source: source)

    expect(booking.reload.booking_folio).to be_present
    expect(folio).to have_attributes(booking_id: booking.id, hotel_id: booking.hotel_id,
      folio_type: "external", payer_type: "ota", is_primary: false, currency: booking.hotel.default_currency)
    expect(folio.booking_billing_party).to have_attributes(party_kind: "ota", booking_source_id: source.id)
    room_code = TransactionCodes::Resolver.for(booking.hotel).room_revenue
    expect(booking.folio_routing_rules.active.find_by(transaction_code: room_code).target_folio).to eq(folio)
  end

  it "is idempotent on webhook retries" do
    expect {
      2.times { described_class.call!(booking:, booking_source: source) }
    }.to change(BookingFolio, :count).by(2).and change(BookingBillingParty, :count).by(1)

    expect(booking.reload.booking_folios.where(payer_type: "ota").count).to eq(1)
  end
end
