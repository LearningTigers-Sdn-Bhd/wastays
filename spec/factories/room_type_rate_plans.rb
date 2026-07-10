FactoryBot.define do
  factory :room_type_rate_plan do
    association :room_type
    association :rate_plan
    pricing_mode { "fixed" }
  end
end
