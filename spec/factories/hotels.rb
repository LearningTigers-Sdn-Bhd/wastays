FactoryBot.define do
  factory :hotel do
    association :account
    name { "#{Faker::Company.name} #{SecureRandom.hex(6)}" }
    address { Faker::Address.street_address }
    city { Faker::Address.city }
    country { "Malaysia" }
    star_rating { 4 }
    status { "setup" }
    sell_mode { "per_room" }

    transient do
      initialize_current_business_date { true }
      accounting_business_date { nil }
    end

    after(:create) do |hotel, evaluator|
      Financials::EnsureDefaultGlMaps.call(hotel)
      Financials::EnsureDefaultTransactionCodes.call(hotel)

      if evaluator.initialize_current_business_date
        date = evaluator.accounting_business_date.presence || hotel.business_date_for(Time.current)
        HotelBusinessDate.initialize_for_hotel!(hotel: hotel, date: date)
      else
        hotel.hotel_business_dates.delete_all
      end
    end

    # Sells by the guest rather than the room. Rate plans inherit this, so set
    # it on the hotel and never on the plan.
    trait :per_person do
      sell_mode { "per_person" }
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
