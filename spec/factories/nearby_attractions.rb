FactoryBot.define do
  factory :nearby_attraction do
    association :hotel
    sequence(:name) { |n| "Nearby Attraction #{n}" }
    description { "Popular spot for hotel guests." }
    address { "123 Attraction Street" }
    city { "Kuala Lumpur" }
    country { "Malaysia" }
  end
end
