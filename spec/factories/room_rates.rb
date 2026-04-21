FactoryBot.define do
  factory :room_rate do
    association :room_type
    date { Date.current }
    price { 99.99 }
    currency { "MYR" }
  end
end
