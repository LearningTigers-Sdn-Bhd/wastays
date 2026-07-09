# frozen_string_literal: true

FactoryBot.define do
  factory :booking_tax_inclusion_override do
    association :booking
    hotel { booking.hotel }
    transaction_code { association(:transaction_code, hotel: hotel) }
    primary_tax_key { "sst_tax" }
    action { "include" }
  end
end
