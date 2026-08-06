require "rails_helper"

RSpec.describe HotelPaymentMethod, type: :model do
  subject(:payment_method) { build(:hotel_payment_method) }

  it "accepts a payment transaction code from the same hotel" do
    expect(payment_method).to be_valid
  end

  it "rejects charge transaction codes" do
    payment_method.transaction_code.kind = "charge"

    expect(payment_method).not_to be_valid
    expect(payment_method.errors[:transaction_code]).to include("must be a payment code")
  end

  it "derives direct and advance categories" do
    payment_method.payment_method_type = "cash"
    expect(payment_method.expected_category).to eq("cash")

    payment_method.payment_method_type = "bank_gateway"
    expect(payment_method.expected_category).to eq("gateway_payment")

    payment_method.guest_advance = true
    expect(payment_method.expected_category).to eq("booking_payment")
  end

  it "allows a default only for direct cash" do
    payment_method.default_cash = true

    expect(payment_method).not_to be_valid
    expect(payment_method.errors[:default_cash]).to include("is only available for direct cash payment methods")
  end

  it "requires the default cash method to remain active" do
    payment_method.payment_method_type = "cash"
    payment_method.default_cash = true
    payment_method.transaction_code.active = false

    expect(payment_method).not_to be_valid
    expect(payment_method.errors[:default_cash]).to include("must remain active")
  end

  it "requires complete surcharge configuration" do
    payment_method.surcharge_posting_type = "percentage"
    payment_method.surcharge_value = 2

    expect(payment_method).not_to be_valid
    expect(payment_method.errors[:base]).to include("Surcharge type, value, and extra charge must be configured together")
  end

  it "calculates fixed and percentage surcharges" do
    payment_method.surcharge_posting_type = "fixed"
    payment_method.surcharge_value = 2
    expect(payment_method.surcharge_amount(100)).to eq(2.to_d)

    payment_method.surcharge_posting_type = "percentage"
    expect(payment_method.surcharge_amount(125)).to eq(2.5.to_d)
  end
end
