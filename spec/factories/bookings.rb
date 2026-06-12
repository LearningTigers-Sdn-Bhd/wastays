FactoryBot.define do
  factory :booking do
    association :hotel
    association :booking_quote
    status { "confirmed" }
    total_amount { 200.0 }
    currency { "MYR" }
    check_in { Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: Date.current, kind: :check_in) }
    check_out { Bookings::ScheduledStay.at_hotel_time(hotel: hotel, value: Date.current + 1.day, kind: :check_out) }
    adults { 2 }
    guest_name { Faker::Name.name }
    guest_email { Faker::Internet.email }
    guest_phone { Faker::PhoneNumber.phone_number }
  end
end
