FactoryBot.define do
  factory :channel_mapping do
    for_hotel # Default trait

    provider { "channex" }
    sequence(:external_id) { |n| "ext_#{n}" }

    trait :for_hotel do
      association :mappable, factory: :hotel
    end

    trait :for_room_type do
      association :mappable, factory: :room_type
    end

    trait :for_rate_plan do
      association :mappable, factory: :rate_plan
    end
  end
end
