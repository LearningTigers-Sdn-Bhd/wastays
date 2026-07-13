FactoryBot.define do
  factory :rate_plan_age_band do
    association :rate_plan
    min_age { 0 }
    max_age { 5 }
    price_multiplier { 0.5 }
    label { "Toddler" }
    sequence(:position)
  end
end
