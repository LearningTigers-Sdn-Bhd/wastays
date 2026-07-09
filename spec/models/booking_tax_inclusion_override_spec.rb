# frozen_string_literal: true

require "rails_helper"

RSpec.describe BookingTaxInclusionOverride, type: :model do
  it "stores one booking-local primary-tax decision" do
    booking = create(:booking)
    code = create(:transaction_code, hotel: booking.hotel)
    override = described_class.create!(hotel: booking.hotel, booking:, transaction_code: code,
      primary_tax_key: "sst_tax", action: "exclude")

    expect(override.tax_key).to eq("primary:sst_tax")
  end

  it "rejects tax identities from another hotel" do
    booking = create(:booking)
    code = create(:transaction_code, hotel: booking.hotel)
    foreign_tax = create(:hotel_tax)
    override = described_class.new(hotel: booking.hotel, booking:, transaction_code: code,
      hotel_tax: foreign_tax, action: "include")

    expect(override).not_to be_valid
    expect(override.errors[:hotel_tax]).to include("must belong to hotel")
  end
end
