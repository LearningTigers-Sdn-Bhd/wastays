# frozen_string_literal: true

require "rails_helper"
require "pdf/reader"
require "stringio"

RSpec.describe Reports::Bookings::GeneratePrimaryGuestInvoice do
  it "selects the finalized guest invoice instead of a corporate folio" do
    booking = create(:booking)
    guest_folio = create(:booking_folio, booking:, status: "closed")
    create(:folio_transaction, booking_folio: guest_folio, amount: 100, description: "Guest charge")
    create(:invoice, booking_folio: guest_folio)

    relationship = create(:hotel_corporate_account, hotel: booking.hotel)
    company_folio = create(:booking_folio, :secondary, booking:, hotel: booking.hotel,
      hotel_corporate_account: relationship, status: "closed")
    create(:folio_transaction, booking_folio: company_folio, amount: 200, description: "Company charge")
    create(:invoice, booking_folio: company_folio)

    text = PDF::Reader.new(StringIO.new(described_class.new(booking:).generate)).pages.map(&:text).join("\n")

    expect(text).to include("Guest charge")
    expect(text).not_to include("Company charge")
  end

  it "rejects a booking without a finalized guest invoice" do
    booking = create(:booking)
    create(:booking_folio, booking:, status: "open")

    expect { described_class.new(booking:).generate }
      .to raise_error(Reports::Bookings::GenerateFolioRecords::UnavailableError, /No finalized guest/)
  end
end
