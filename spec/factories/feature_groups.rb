FactoryBot.define do
  factory :feature_group do
    sequence(:name) { |n| "Group #{n}" }
    sequence(:slug) { |n| "group_#{n}" }
    position { 0 }
  end
end
