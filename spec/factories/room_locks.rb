FactoryBot.define do
  factory :room_lock do
    association :hotel
    association :user
    room_type { association :room_type, hotel: hotel }
    sequence(:room_number) { |n| "Room #{n}" }
    expires_at { 10.minutes.from_now }
  end
end
