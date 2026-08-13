# frozen_string_literal: true

FactoryBot.define do
  factory :channel_settlement do
    association :hotel
    association :booking_source, kind: "ota"
    sequence(:channel_manager_reference) { |n| "channel-settlement-#{n}" }
    provider { "channex" }
    collection_by { "ota" }
    settlement_method { "bank_transfer" }
    status { "awaiting_ota_settlement" }
    currency { "MYR" }
    gross_amount { 100 }
    commission_amount { 10 }
    expected_net_amount { 90 }
  end
end
