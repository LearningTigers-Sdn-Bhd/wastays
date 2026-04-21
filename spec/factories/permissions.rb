FactoryBot.define do
  factory :permission do
    sequence(:name) { |n| "Manage Resource #{n}" }
    sequence(:slug) { |n| "manage-resource-#{n}" }
  end
end
