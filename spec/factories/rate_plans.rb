FactoryBot.define do
  factory :rate_plan do
    name { "Standard Rate" }
    association :hotel
    sell_mode { "per_room" }
    currency { "MYR" }

    transient do
      room_type { nil }
    end

    after(:create) do |rate_plan, evaluator|
      if evaluator.room_type
        create(:room_type_rate_plan, rate_plan: rate_plan, room_type: evaluator.room_type)
      end
    end

    trait :age_banded do
      sell_mode { "per_person" }

      after(:create) do |rate_plan|
        create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 4, max_age: 11, price_value: 0.4, label: "Child")
        create(:rate_plan_age_band, rate_plan: rate_plan, min_age: 12, max_age: 17, price_value: 0.2, label: "Teen")
      end
    end
  end
end
