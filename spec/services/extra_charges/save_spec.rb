require "rails_helper"

RSpec.describe ExtraCharges::Save do
  let(:hotel) { create(:hotel) }

  def attributes(overrides = {})
    {
      name: "Airport Transfer",
      code: "airport",
      description: "One-way transfer",
      category: "other",
      pricing_type: "fixed",
      rate_value: "75",
      charging_unit: "per_item",
      allow_amount_override: "0",
      active: "1"
    }.merge(overrides)
  end

  def new_extra_charge
    hotel.hotel_extra_charges.build(
      transaction_code: hotel.transaction_codes.build(kind: "charge", category: "other", active: true),
      pricing_type: "manual",
      charging_unit: "per_item",
      allow_amount_override: true
    )
  end

  it "creates the registry record and backing transaction code atomically" do
    extra_charge = new_extra_charge

    result = described_class.call(extra_charge: extra_charge, attributes: attributes, tax_rule_keys: [])

    expect(result).to be_success
    expect(extra_charge).to be_persisted
    expect(extra_charge.transaction_code).to have_attributes(
      code: "AIRPORT", name: "Airport Transfer", kind: "charge", category: "other",
      system_required: false, active: true
    )
    expect(extra_charge.transaction_code.system_key).to eq("extra_charge_airport")
  end

  it "does not persist either record when the normalized code collides" do
    create(:transaction_code, hotel: hotel, code: "AIRPORT")
    extra_charge = new_extra_charge
    counts = [ HotelExtraCharge.count, TransactionCode.count ]

    result = described_class.call(extra_charge: extra_charge, attributes: attributes, tax_rule_keys: [])

    expect(result).not_to be_success
    expect([ HotelExtraCharge.count, TransactionCode.count ]).to eq(counts)
    expect(extra_charge.errors[:code]).to include("has already been taken")
  end

  it "keeps the stable system key when staff rename and deactivate a charge" do
    extra_charge = create(:hotel_extra_charge, hotel: hotel)
    original_system_key = extra_charge.transaction_code.system_key

    result = described_class.call(
      extra_charge: extra_charge,
      attributes: attributes(name: "Hotel Shuttle", code: "shuttle", active: "0"),
      tax_rule_keys: []
    )

    expect(result).to be_success
    expect(extra_charge.transaction_code.reload).to have_attributes(
      code: "SHUTTLE", name: "Hotel Shuttle", system_key: original_system_key, active: false
    )
  end

  it "synchronizes selected hotel tax rules on the backing code" do
    hotel.update!(sst_enabled: true)
    tax = create(:hotel_tax, hotel: hotel)
    extra_charge = new_extra_charge

    result = described_class.call(
      extra_charge: extra_charge,
      attributes: attributes,
      tax_rule_keys: [ "primary:sst_tax", "hotel_tax:#{tax.id}" ]
    )

    expect(result).to be_success
    expect(extra_charge.transaction_code.tax_rule_keys).to match_array(
      [ "primary:sst_tax", "hotel_tax:#{tax.id}" ]
    )
  end
end
