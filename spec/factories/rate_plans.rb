FactoryBot.define do
  factory :rate_plan do
    name { "Standard Rate" }
    association :room_type
    sell_mode { "per_room" }
    currency { "MYR" }
  end
end
