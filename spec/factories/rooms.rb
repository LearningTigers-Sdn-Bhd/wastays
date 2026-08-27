# frozen_string_literal: true

FactoryBot.define do
  factory :room do
    association :room_type
    hotel { room_type.hotel }
    room_group { nil }
    sequence(:number) { |number| "R#{number}" }
    position { 0 }
    archived_at { nil }
  end
end
