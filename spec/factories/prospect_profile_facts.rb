FactoryBot.define do
  factory :prospect_profile_fact do
    association :prospect
    sequence(:category) { |n| "category_#{n}" }
    value { "Sample value" }
  end
end
