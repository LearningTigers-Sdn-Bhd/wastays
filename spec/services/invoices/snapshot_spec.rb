# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Snapshot do
  it "freezes folio transactions and issue-time totals" do
    folio = create(:booking_folio, status: "closed", currency: "MYR")
    create(:folio_transaction, booking_folio: folio, transaction_type: "charge", amount: 125)
    create(:folio_transaction, booking_folio: folio, transaction_type: "payment", category: "cash", amount: 25)

    snapshot = described_class.call(folio:)

    expect(snapshot.dig(:folio, :id)).to eq(folio.id)
    expect(snapshot.fetch(:transactions).size).to eq(2)
    expect(snapshot.fetch(:totals)).to include(charges: "125.0", payments: "25.0", balance: "100.0", currency: "MYR")
  end

  it "captures the hotel-specific corporate billing address" do
    relationship = create(:hotel_corporate_account,
      billing_address_line1: "Lot 8",
      billing_city: "Kota Kinabalu",
      billing_country: "Malaysia")
    folio = create(:booking_folio, :secondary,
      hotel: relationship.hotel,
      booking: create(:booking, hotel: relationship.hotel),
      payer_type: "company",
      hotel_corporate_account: relationship)

    snapshot = described_class.call(folio:)

    expect(snapshot.dig(:payer, :billing_address)).to include(
      "address_line1" => "Lot 8",
      "city" => "Kota Kinabalu",
      "country" => "Malaysia"
    )
  end

  it "captures guest contact details and the primary stay address" do
    booking = create(:booking,
      guest_email: "john@example.com",
      guest_phone: "+60123456789",
      guest_home_address: "Legacy address",
      guest_city: "Legacy city",
      guest_address_country: "Malaysia")
    guest = create(:guest,
      home_address: "No. 12, Jalan Ampang",
      city: "Kuala Lumpur",
      state_code: "14",
      postal_code: "50450",
      address_country: "Malaysia")
    create(:booking_guest, booking:, guest:, is_primary: true)
    folio = create(:booking_folio, booking:, hotel: booking.hotel, payer_type: "guest", status: "closed")

    snapshot = described_class.call(folio:)

    expect(snapshot.fetch(:payer)).to include(
      contact_email: "john@example.com",
      contact_phone: "+60123456789"
    )
    expect(snapshot.dig(:payer, :billing_address)).to include(
      "address_line1" => "No. 12, Jalan Ampang",
      "city" => "Kuala Lumpur",
      "state" => "Wilayah Persekutuan Kuala Lumpur",
      "postal_code" => "50450",
      "country" => "Malaysia"
    )
  end
end
