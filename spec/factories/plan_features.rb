FactoryBot.define do
  factory :plan_feature do
    association :plan
    association :feature
    enabled { true }
    level { nil }
    addon { false }
  end
end
