# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoice do
  it "allows one immutable document per booking folio" do
    invoice = create(:invoice)
    duplicate = build(:invoice, booking_folio: invoice.booking_folio, hotel: invoice.hotel)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:booking_folio_id]).to be_present
    expect(invoice.update(invoice_reference: "CHANGED")).to be(false)
    expect(invoice.errors[:base]).to include("Invoice identity is immutable after creation.")
  end

  it "keeps settled and direct-bill number sequences independently unique" do
    settled = create(:invoice, invoice_number: 77)
    booking = create(:booking, hotel: settled.hotel)
    direct = build(:invoice, :direct_bill,
      booking_folio: create(:booking_folio, :secondary, booking:, hotel: settled.hotel),
      hotel: settled.hotel,
      invoice_number: 77,
      invoice_reference: "#{settled.hotel.hotel_prefix}-4#{'77'.rjust(7, '0')}")

    expect(direct).to be_valid
  end
end
