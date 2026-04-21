FactoryBot.define do
  factory :property_policy do
    association :hotel
    check_in_time { "15:00" }
    check_out_time { "12:00" }
    cancellation_policy { "Free cancellation 48 hours before check-in." }
    currency { "MYR" }
    usd_rate { 4.50 }
  end
end
