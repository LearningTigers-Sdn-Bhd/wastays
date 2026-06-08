FactoryBot.define do
  factory :plan do
    sequence(:name) { |n| "Plan #{n}" }
    sequence(:slug) { |n| "plan-#{n}" }
    position { 0 }
    most_popular { false }
    active { true }
  end
end
