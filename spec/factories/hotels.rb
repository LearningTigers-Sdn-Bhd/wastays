FactoryBot.define do
  factory :hotel do
    association :account
    name { Faker::Company.name }
    address { Faker::Address.street_address }
    city { Faker::Address.city }
    country { "Malaysia" }
    star_rating { 4 }
    status { "registered" }

    trait :with_ai_concierge do
      ai_provider_enabled { true }
      ai_provider_name { "openai" }
      ai_provider_key { "test-api-key" }
    end
  end
end
