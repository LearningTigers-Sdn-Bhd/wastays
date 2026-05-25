FactoryBot.define do
  factory :booking do
    association :hotel
    association :booking_quote
    status { "confirmed" }
    total_amount { 200.0 }
    currency { "MYR" }
    check_in { Date.current }
    check_out { Date.current + 1.day }
    adults { 2 }
    guest_name { Faker::Name.name }
    guest_email { Faker::Internet.email }
    guest_phone { Faker::PhoneNumber.phone_number }
  end
end
