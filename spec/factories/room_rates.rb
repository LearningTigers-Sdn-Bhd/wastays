FactoryBot.define do
  factory :room_rate do
    room_type { nil }
    date { "2026-03-25" }
    price { "9.99" }
    currency { "MyString" }
  end
end
