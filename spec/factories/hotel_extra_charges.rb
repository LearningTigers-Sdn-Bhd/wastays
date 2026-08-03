FactoryBot.define do
  factory :hotel_extra_charge do
    association :hotel
    transaction_code { association(:transaction_code, hotel: hotel, kind: "charge", category: "other") }
    description { "An additional hotel service" }
    pricing_type { "manual" }
    charging_unit { "per_item" }
    allow_amount_override { true }
    sequence(:position)
  end
end
