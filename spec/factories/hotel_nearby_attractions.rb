# frozen_string_literal: true

FactoryBot.define do
  factory :hotel_nearby_attraction do
    association :hotel
    association :attraction
    description { nil }
  end
end
