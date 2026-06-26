# frozen_string_literal: true

FactoryBot.define do
  factory :corporate_ar_payment_intent do
    association :hotel_corporate_account
    hotel { hotel_corporate_account.hotel }
    corporate_account { hotel_corporate_account.corporate_account }
    user { association :user, :corporate, account: corporate_account }
    amount { 100.0 }
    currency { hotel.default_currency.presence || "MYR" }
    gateway { "razorpay" }
    status { "pending" }
    expires_at { 30.minutes.from_now }
    invoice_snapshots { [] }
    remittance_suggestions { [] }
    metadata { {} }
  end
end
