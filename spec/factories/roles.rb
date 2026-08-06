FactoryBot.define do
  factory :role do
    association :account
    sequence(:name) { |n| "Role #{n}" }
    slug { "role-#{SecureRandom.hex(6)}" }
  end
end
