FactoryBot.define do
  factory :nearby_attraction, class: "Attraction" do
    transient do
      hotel { association :hotel }
      description { "Popular spot for hotel guests." }
    end

    sequence(:name) { |n| "Nearby Attraction #{n}" }
    shared_summary { description }
    address { "123 Attraction Street" }
    city { "Kuala Lumpur" }
    country { "Malaysia" }
    status { "approved" }

    after(:create) do |attraction, evaluator|
      create(
        :hotel_nearby_attraction,
        hotel: evaluator.hotel,
        attraction: attraction,
        description: evaluator.description
      )
    end
  end
end
