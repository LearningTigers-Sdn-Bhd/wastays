# frozen_string_literal: true

FactoryBot.define do
  factory :ar_payment_allocation do
    association :ar_payment
    ar_invoice { association(:ar_invoice, hotel: ar_payment.hotel, hotel_corporate_account: ar_payment.hotel_corporate_account) }
    amount { 100.0 }
    metadata { {} }
  end
end
