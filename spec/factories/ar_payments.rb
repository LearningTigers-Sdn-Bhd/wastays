# frozen_string_literal: true

FactoryBot.define do
  factory :ar_payment do
    association :hotel_corporate_account
    hotel { hotel_corporate_account.hotel }
    amount { 100.0 }
    currency { hotel.default_currency.presence || "MYR" }
    sequence(:reference_number) { |n| "AR-PAY-#{n}" }
    received_at { Date.current }
    payment_method { "bank_transfer" }
    metadata { {} }
  end
end
