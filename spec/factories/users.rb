FactoryBot.define do
  factory :user do
    association :account
    name { Faker::Name.name }
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    role { "hotel_staff" }

    trait :superadmin do
      role { "superadmin" }
    end

    trait :admin do
      role { "admin" }
    end
  end
end
