require "rails_helper"

RSpec.describe PaymentMethods::EnsureDefaults do
  let(:hotel) { create(:hotel) }

  it "wraps the six existing payment codes idempotently" do
    described_class.call(hotel)

    expect(hotel.hotel_payment_methods.count).to eq(6)
    expect(hotel.hotel_payment_methods.joins(:transaction_code).pluck("transaction_codes.system_key"))
      .to match_array(%w[cash_payment cash_prepayment card_payment bank_payment gateway_manual_recovery_payment ota_collected_payment])
    expect(hotel.hotel_payment_methods.find_by!(default_cash: true).transaction_code.system_key).to eq("cash_payment")
    expect(hotel.hotel_payment_methods.joins(:transaction_code).where(transaction_codes: { system_key: %w[cash_prepayment bank_payment ota_collected_payment] }))
      .to all(be_guest_advance)
    expect(hotel.hotel_payment_methods.joins(:transaction_code).find_by!(transaction_codes: { system_key: "cash_prepayment" }))
      .to have_attributes(payment_method_type: "cash", guest_advance: true, default_cash: false)

    expect { described_class.call(hotel) }.not_to change(HotelPaymentMethod, :count)
  end
end
