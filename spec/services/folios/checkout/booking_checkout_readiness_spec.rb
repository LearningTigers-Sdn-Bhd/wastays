# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Checkout::BookingCheckoutReadiness do
  let(:hotel) { create(:hotel) }
  let(:booking) { create(:booking, hotel: hotel, status: "checked_in", currency: "MYR") }
  let!(:guest_folio) { create(:booking_folio, hotel: hotel, booking: booking, label: "Guest Folio") }
  let!(:company_folio) { create(:booking_folio, :secondary, hotel: hotel, booking: booking, label: "Company Folio") }

  it "blocks checkout when any folio has a non-zero projected balance" do
    create(:folio_transaction, booking_folio: company_folio, transaction_type: "charge", category: "accommodation", amount: 100)

    result = described_class.call(booking: booking, hotel: hotel)

    expect(result).not_to be_ready
    expect(result.projected_balance).to eq(100.to_d)
    expect(result.blockers.join).to include("Company Folio")
  end
end
