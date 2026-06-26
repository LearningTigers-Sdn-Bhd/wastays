FactoryBot.define do
  factory :user do
    association :account
    name { Faker::Name.name }
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    role { "hotel_staff" }
    time_zone { User::DEFAULT_TIME_ZONE }

    trait :superadmin do
      role { "superadmin" }
    end

    trait :admin do
      role { "admin" }
    end

    trait :salesperson do
      role { "salesperson" }
    end

    trait :corporate do
      account { association :account, :corporate }
      role { "corporate" }
    end
  end
end
