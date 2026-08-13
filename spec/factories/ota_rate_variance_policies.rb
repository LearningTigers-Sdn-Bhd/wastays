# frozen_string_literal: true

FactoryBot.define do
  factory :ota_rate_variance_policy do
    association :hotel
    mode { "recommended" }
    currency { hotel.default_currency }
  end
end
