FactoryBot.define do
  factory :feature do
    association :feature_group
    sequence(:name) { |n| "Feature #{n}" }
    sequence(:slug) { |n| "feature_#{n}" }
    position { 0 }
    leveled { false }
    addon { false }
  end
end
