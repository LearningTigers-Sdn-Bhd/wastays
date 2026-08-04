require "rails_helper"

RSpec.describe HotelDiscount, type: :model do
  it "requires an adjustment discount transaction code from the same hotel" do
    discount = build(:hotel_discount)
    discount.transaction_code.kind = "charge"

    expect(discount).not_to be_valid
    expect(discount.errors[:transaction_code]).to include("must be an adjustment discount code")
  end

  it "requires selected charge codes for the selected scope" do
    discount = build(:hotel_discount, application_scope: "selected_charges")

    expect(discount).not_to be_valid
    expect(discount.errors[:applicable_transaction_codes]).to be_present
  end

  it "accepts same-hotel non-tax charge codes for the selected scope" do
    hotel = create(:hotel)
    discount = build(:hotel_discount, hotel:, application_scope: "selected_charges")
    discount.applicable_transaction_codes = [ create(:transaction_code, hotel:) ]

    expect(discount).to be_valid
  end

  it "enforces percentage pricing and override rules" do
    discount = build(:hotel_discount, pricing_type: "percentage", rate_value: 101, allow_amount_override: true)

    expect(discount).not_to be_valid
    expect(discount.errors[:rate_value]).to include("must be 100 or less for percentage pricing")
    expect(discount.errors[:allow_amount_override]).to be_present
  end
end
