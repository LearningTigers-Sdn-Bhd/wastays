FactoryBot.define do
  factory :hotel_business_date do
    association :hotel
    business_date { Date.current }
    status { "open" }
    opened_at { Time.current }
    blockers_snapshot { {} }
  end
end
