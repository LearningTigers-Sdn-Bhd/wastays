# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocumentIdentifiers::Issuer do
  let(:hotel) { create(:hotel, hotel_prefix: "HTL") }

  it "maintains an independent sequence for each hotel business year" do
    first_2026 = described_class.issue!(hotel:, type: :invoice, year: 2026)
    second_2026 = described_class.issue!(hotel:, type: :invoice, year: 2026)
    first_2027 = described_class.issue!(hotel:, type: :invoice, year: 2027)

    expect(first_2026.to_h).to eq(number: 1, year: 2026, reference: "HTL-26700001")
    expect(second_2026.to_h).to eq(number: 2, year: 2026, reference: "HTL-26700002")
    expect(first_2027.to_h).to eq(number: 1, year: 2027, reference: "HTL-27700001")
  end

  it "shares reservation sequences between bookings and group bookings within a year" do
    create(:booking, hotel:, reservation_year: 2026, reservation_number: 4, reservation_reference: "HTL-26100004")
    create(:group_booking, hotel:, reservation_year: 2026, reservation_number: 5, reservation_reference: "HTL-26100005")

    allocation = described_class.issue!(hotel:, type: :reservation, year: 2026)

    expect(allocation.to_h).to eq(number: 6, year: 2026, reference: "HTL-26100006")
  end

  it "uses the hotel business year by default" do
    allow(hotel).to receive(:current_business_date).and_return(Date.new(2027, 1, 1))

    allocation = described_class.issue!(hotel:, type: :folio)

    expect(allocation.year).to eq(2027)
    expect(allocation.reference).to eq("HTL-27300001")
  end
end
