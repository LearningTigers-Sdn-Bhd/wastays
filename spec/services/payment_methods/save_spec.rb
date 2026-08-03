require "rails_helper"

RSpec.describe PaymentMethods::Save do
  let(:hotel) { create(:hotel) }

  it "saves the registry item and transaction code atomically" do
    payment_method = hotel.hotel_payment_methods.build(
      transaction_code: hotel.transaction_codes.build(kind: "payment", category: "gateway_payment", active: true),
      payment_method_type: "bank_gateway"
    )

    result = described_class.call(
      payment_method: payment_method,
      attributes: { name: "DuitNow", code: "duit-now", payment_method_type: "bank_gateway", guest_advance: "1", active: "1" }
    )

    expect(result.success?).to be(true)
    expect(payment_method.reload.transaction_code).to have_attributes(
      name: "DuitNow", code: "DUIT_NOW", kind: "payment", category: "booking_payment", active: true
    )
  end

  it "moves the default cash selection atomically" do
    PaymentMethods::EnsureDefaults.call(hotel)
    original = hotel.hotel_payment_methods.find_by!(default_cash: true)
    code = hotel.transaction_codes.create!(system_key: "cash_two", code: "CASH2", name: "Second Cash", kind: "payment", category: "cash")
    replacement = hotel.hotel_payment_methods.create!(transaction_code: code, payment_method_type: "cash")

    result = described_class.call(
      payment_method: replacement,
      attributes: { name: "Second Cash", code: "CASH2", payment_method_type: "cash", default_cash: "1", active: "1" }
    )

    expect(result.success?).to be(true)
    expect(replacement.reload).to be_default_cash
    expect(original.reload).not_to be_default_cash
  end
end
