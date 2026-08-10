# frozen_string_literal: true

FactoryBot.define do
  factory :channel_settlement_receipt do
    association :hotel
    association :booking_source, kind: "ota"
    hotel_payment_method { association(:hotel_payment_method, hotel: hotel) }
    association :recorded_by, factory: :user
    settlement_method { "bank_transfer" }
    amount { 90 }
    currency { "MYR" }
    received_at { Time.current }
    sequence(:external_reference) { |n| "channel-receipt-#{n}" }
  end
end
