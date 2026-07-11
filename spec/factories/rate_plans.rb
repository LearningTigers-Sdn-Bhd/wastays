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
  end
end
