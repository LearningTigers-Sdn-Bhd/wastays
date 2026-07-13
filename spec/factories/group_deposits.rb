# frozen_string_literal: true

FactoryBot.define do
  factory :group_deposit do
    association :group_booking
    hotel { group_booking.hotel }
    amount { 1_000 }
    currency { hotel.default_currency }
    payment_method { "bank_transfer" }
    status { "received" }
    received_at { Time.current }
  end
end
