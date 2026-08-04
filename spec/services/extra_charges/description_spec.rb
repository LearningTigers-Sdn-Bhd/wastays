require "rails_helper"

RSpec.describe ExtraCharges::Description do
  let(:hotel) { create(:hotel, default_currency: "MYR") }

  def description_for(extra_charge, **attributes)
    described_class.call(extra_charge: extra_charge, currency: "MYR", **attributes)
  end

  it "uses staff text for manual pricing and falls back to the registry name" do
    extra_charge = create(:hotel_extra_charge, hotel: hotel, pricing_type: "manual")

    expect(description_for(extra_charge, submitted_description: "Lost key · Room 204")).to eq("Lost key · Room 204")
    expect(description_for(extra_charge, submitted_description: "")).to eq(extra_charge.name)
  end

  it "formats fixed pricing compactly and omits a quantity of one" do
    extra_charge = create(:hotel_extra_charge, hotel: hotel, pricing_type: "fixed", rate_value: 5)

    expect(description_for(extra_charge, quantity: 1, amount: 5, calculated_amount: 5)).to eq("#{extra_charge.name} · MYR 5.00")
    expect(description_for(extra_charge, quantity: 2, amount: 10, calculated_amount: 10)).to eq("#{extra_charge.name} · 2 × MYR 5.00")
  end

  it "formats percentage pricing from its authoritative base" do
    extra_charge = create(:hotel_extra_charge, hotel: hotel, pricing_type: "percentage", rate_value: 10,
      percentage_basis: "room_charges", allow_amount_override: false)

    expect(description_for(extra_charge, amount: 20, base_amount: 200)).to eq("#{extra_charge.name} · 10% × MYR 200.00")
  end

  it "identifies fixed total overrides" do
    extra_charge = create(:hotel_extra_charge, hotel: hotel, pricing_type: "fixed", rate_value: 5)

    expect(description_for(extra_charge, quantity: 2, amount: 8, calculated_amount: 10))
      .to eq("#{extra_charge.name} · 2 × MYR 5.00 · override MYR 8.00")
  end

  it "formats scheduled dates with actual rates and identifies rate overrides" do
    extra_charge = create(:hotel_extra_charge, hotel: hotel, pricing_type: "fixed", rate_value: 50)

    expect(description_for(extra_charge, quantity: 2, amount: 90, calculated_amount: 90, unit_rate: 45, date: Date.new(2026, 8, 3)))
      .to eq("#{extra_charge.name} · 2 × MYR 45.00 · rate override · 2026-08-03")
  end
end
