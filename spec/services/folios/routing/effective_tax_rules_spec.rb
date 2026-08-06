# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::EffectiveTaxRules do
  it "applies booking-local exclusions without changing hotel defaults" do
    booking = create(:booking)
    code = create(:transaction_code, hotel: booking.hotel)
    default = code.transaction_code_taxes.create!(primary_tax_key: "sst_tax")
    create(:booking_tax_inclusion_override, booking:, hotel: booking.hotel, transaction_code: code,
      primary_tax_key: "sst_tax", action: "exclude")

    expect(described_class.call(booking:, transaction_code: code)).to be_empty
    expect(default.reload).to be_persisted
  end
end
