# frozen_string_literal: true

FactoryBot.define do
  factory :ota_financial_snapshot do
    association :hotel
    association :booking_source, kind: "ota"
    booking { FactoryBot.build(:booking, hotel: hotel) }
    group_booking { nil }
    provider { "channex" }
    sequence(:channel_manager_reference) { |n| "ota-reservation-#{n}" }
    sequence(:provider_revision_id) { |n| "revision-#{n}" }
    provider_revision_number { nil }
    original_currency { "MYR" }
    original_gross_amount { 200.to_d }
    currency { "MYR" }
    gross_amount { 200.to_d }
    original_accommodation_amount { 200.to_d }
    accommodation_amount { 200.to_d }
    exchange_rate { 1.to_d }
    exchange_rate_source { "identity" }
    reconciliation_status { "balanced" }

    trait :for_group_booking do
      booking { nil }
      group_booking { FactoryBot.build(:group_booking, hotel: hotel) }
    end
  end
end
