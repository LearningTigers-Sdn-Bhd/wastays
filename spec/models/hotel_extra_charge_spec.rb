require "rails_helper"

RSpec.describe HotelExtraCharge do
  subject(:extra_charge) { build(:hotel_extra_charge) }

  it "accepts a normalized charge transaction code" do
    expect(extra_charge).to be_valid
  end

  it "requires the transaction code to belong to the same hotel" do
    extra_charge.transaction_code = build(:transaction_code, hotel: create(:hotel))

    expect(extra_charge).not_to be_valid
    expect(extra_charge.errors[:transaction_code]).to include("must belong to the same hotel")
  end

  it "requires a charge transaction code" do
    extra_charge.transaction_code.kind = "payment"
    extra_charge.transaction_code.category = "cash"

    expect(extra_charge).not_to be_valid
    expect(extra_charge.errors[:transaction_code]).to include("must be a charge code")
  end

  it "limits registry-managed codes to ten characters" do
    extra_charge.transaction_code.code = "AIRPORTBUS"
    expect(extra_charge).to be_valid

    extra_charge.transaction_code.code = "AIRPORTBUS2"
    expect(extra_charge).not_to be_valid
    expect(extra_charge.errors[:code]).to include("must be 10 characters or fewer")
  end

  it "validates conditional pricing fields" do
    extra_charge.pricing_type = "fixed"
    extra_charge.rate_value = nil
    expect(extra_charge).not_to be_valid

    extra_charge.rate_value = 25
    expect(extra_charge).to be_valid

    extra_charge.pricing_type = "percentage"
    extra_charge.percentage_basis = nil
    expect(extra_charge).not_to be_valid

    extra_charge.percentage_basis = "room_charges"
    extra_charge.allow_amount_override = false
    extra_charge.rate_value = 101
    expect(extra_charge).not_to be_valid
    expect(extra_charge.errors[:rate_value]).to include("must be 100 or less for percentage pricing")
  end

  it "does not allow staff overrides for percentage pricing" do
    extra_charge.assign_attributes(
      pricing_type: "percentage", rate_value: 10, percentage_basis: "room_charges",
      allow_amount_override: true
    )

    expect(extra_charge).not_to be_valid
    expect(extra_charge.errors[:allow_amount_override]).to include("must be disabled for percentage pricing")
  end

  it "does not duplicate transaction-code-owned fields" do
    expect(described_class.column_names).not_to include("name", "code", "category", "active", "currency")
  end
end
