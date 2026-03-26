FactoryBot.define do
  factory :booking_quote do
    association :hotel
    sequence(:token) { |n| "tok_#{n}" }
    total_amount { 200.0 }
    currency { "MYR" }
    status { "active" }
    expires_at { 1.hour.from_now }
    check_in { Date.today }
    check_out { Date.today + 1.day }
    adults { 2 }
  end
end
