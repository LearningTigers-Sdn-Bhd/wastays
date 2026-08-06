FactoryBot.define do
  factory :plan do
    sequence(:name) { |n| "Plan #{n}" }
    slug { "plan-#{SecureRandom.hex(6)}" }
    position { 0 }
    most_popular { false }
    active { true }
  end
end
