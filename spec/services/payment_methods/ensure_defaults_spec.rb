require "rails_helper"

RSpec.describe PaymentMethods::EnsureDefaults do
  let(:hotel) { create(:hotel) }

  it "wraps the five existing payment codes idempotently" do
    described_class.call(hotel)

    expect(hotel.hotel_payment_methods.count).to eq(5)
    expect(hotel.hotel_payment_methods.joins(:transaction_code).pluck("transaction_codes.system_key"))
      .to match_array(%w[cash_payment card_payment bank_payment gateway_manual_recovery_payment ota_collected_payment])
    expect(hotel.hotel_payment_methods.find_by!(default_cash: true).transaction_code.system_key).to eq("cash_payment")
    expect(hotel.hotel_payment_methods.joins(:transaction_code).where(transaction_codes: { system_key: %w[bank_payment ota_collected_payment] }))
      .to all(be_guest_advance)

    expect { described_class.call(hotel) }.not_to change(HotelPaymentMethod, :count)
  end
end
