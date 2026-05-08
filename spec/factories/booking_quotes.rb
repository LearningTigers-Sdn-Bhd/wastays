FactoryBot.define do
  factory :booking_quote do
    association :hotel
    sequence(:token) { |n| "tok_#{n}" }
    total_amount { 200.0 }
    currency { "MYR" }
    status { "active" }
    expires_at { 1.hour.from_now }
    check_in { Date.current }
    check_out { Date.current + 1.day }
    adults { 2 }
  end
end
