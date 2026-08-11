# frozen_string_literal: true

FactoryBot.define do
  factory :ota_financial_component_mapping do
    association :hotel
    association :booking_source, kind: "ota"
    transaction_code { association :transaction_code, hotel: hotel, kind: "charge", category: "other" }
    provider { "channex" }
    component_kind { "fee" }
    normalized_provider_type { "service_charge" }
    sequence(:normalized_provider_name) { |n| "cleaning_fee_#{n}" }
    active { true }
  end
end
