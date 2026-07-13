FactoryBot.define do
  factory :rate_plan_age_band do
    association :rate_plan
    min_age { 0 }
    max_age { 5 }
    pricing_mode { "multiplier" }
    price_value { 0.5 }
    label { "Toddler" }
    sequence(:position)

    trait :amount do
      pricing_mode { "amount" }
      price_value { 30.0 }
    end
  end
end
