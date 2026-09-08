FactoryBot.define do
  factory :hotel_transport_detail do
    association :hotel
    airport_distance_km { 32 }
    airport_travel_minutes { 45 }
    directions { "Take exit 14 from the coastal highway." }
    parking_availability { "none" }

    trait :with_transfer do
      airport_transfer_offered { true }
      airport_transfer_price { 120.00 }
      airport_transfer_lead_hours { 24 }
      pickup_point { "Main lobby" }
    end

    trait :with_parking do
      parking_availability { "on_site" }
      parking_type { "valet" }
      parking_price { 25.00 }
      parking_price_unit { "night" }
      parking_spaces { 40 }
      parking_height_limit_m { 2.10 }
      parking_ev_charging { true }
    end
  end
end
