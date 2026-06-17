FactoryBot.define do
  factory :hotel_tax do
    association :hotel
    name { "Heritage Fee" }
    code { nil }
    rate_type { "flat" }
    amount { 2.0 }
    enabled { true }
    foreign_guests_only { false }
  end
end
