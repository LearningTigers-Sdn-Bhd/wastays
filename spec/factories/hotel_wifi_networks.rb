FactoryBot.define do
  factory :hotel_wifi_network do
    association :hotel
    sequence(:label) { |number| "Guest network #{number}" }
    sequence(:ssid) { |number| "HotelGuest#{number}" }
    password { "guest-secret" }
    security_type { "protected" }
    access_scope { "checked_in_guests" }
    active { true }
  end
end
