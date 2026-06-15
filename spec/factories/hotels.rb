FactoryBot.define do
  factory :hotel do
    association :account
    name { "#{Faker::Company.name} #{SecureRandom.hex(6)}" }
    address { Faker::Address.street_address }
    city { Faker::Address.city }
    country { "Malaysia" }
    star_rating { 4 }
    status { "registered" }

    transient do
      initialize_current_business_date { true }
      accounting_business_date { nil }
    end

    after(:create) do |hotel, evaluator|
      if evaluator.initialize_current_business_date
        if evaluator.accounting_business_date
          hotel.current_business_date_record&.update!(business_date: evaluator.accounting_business_date.to_date)
        end
      else
        hotel.hotel_business_dates.delete_all
      end
    end

    trait :without_current_business_date do
      initialize_current_business_date { false }
    end

    trait :with_ai_concierge do
      ai_provider_enabled { true }
      ai_provider_name { "openai" }
      ai_provider_key { "test-api-key" }
    end
  end
end
