FactoryBot.define do
  factory :hotel_business_date do
    association :hotel, factory: [ :hotel, :without_current_business_date ]
    business_date { Date.current }
    status { "open" }
    opened_at { Time.current }
    blockers_snapshot { {} }
  end
end
