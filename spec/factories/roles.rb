FactoryBot.define do
  factory :role do
    association :account
    sequence(:name) { |n| "Role #{n}" }
    sequence(:slug) { |n| "role-#{n}" }
  end
end
