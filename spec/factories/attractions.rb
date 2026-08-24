# frozen_string_literal: true

FactoryBot.define do
  factory :attraction do
    sequence(:name) { |number| "Attraction #{number}" }
    normalized_name { Attractions::Fingerprint.normalize_name(name) }
    sequence(:latitude) { |number| BigDecimal("5.98000") + (number * BigDecimal("0.00001")) }
    sequence(:longitude) { |number| BigDecimal("116.07000") + (number * BigDecimal("0.00001")) }
    google_maps_url do
      "https://www.google.com/maps/place/#{CGI.escape(name)}/@#{latitude},#{longitude},15z"
    end
    coordinate_fingerprint do
      Attractions::Fingerprint.call(name: name, latitude: latitude, longitude: longitude)
    end
    status { "approved" }

    trait :pending do
      status { "pending" }
      association :source_hotel, factory: :hotel
    end

    trait :rejected do
      status { "rejected" }
      review_note { "The submitted place is not a tourist attraction." }
    end

    trait :archived do
      status { "archived" }
      archived_from_status { "approved" }
    end

    trait :legacy do
      latitude { nil }
      longitude { nil }
      google_maps_url { nil }
      coordinate_fingerprint { nil }
      city { "Kota Kinabalu" }
      country { "Malaysia" }
    end
  end
end
