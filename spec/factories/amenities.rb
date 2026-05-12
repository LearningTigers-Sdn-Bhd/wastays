FactoryBot.define do
  factory :amenity do
    sequence(:name) { |n| "Amenity #{n}" }
    sequence(:slug) { |n| "amenity-#{n}" }
    amenity_type { "hotel" }
    category { "General" }
    icon { "star" }

    trait :hotel do
      amenity_type { "hotel" }
    end

    trait :room do
      amenity_type { "room" }
    end
  end
end
