FactoryBot.define do
  factory :hotel_payment_method do
    association :hotel
    transaction_code { association(:transaction_code, hotel: hotel, kind: "payment", category: "gateway_payment") }
    payment_method_type { "bank_gateway" }
    default_cash { false }
    guest_advance { false }
    sequence(:position)
  end
end
