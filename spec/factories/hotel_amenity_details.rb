FactoryBot.define do
  factory :hotel_amenity_detail do
    association :hotel
    association :amenity, :hotel
    location { "Ground floor" }
    opening_hours { "Daily, 7:00 AM to 10:00 PM" }
  end
end
