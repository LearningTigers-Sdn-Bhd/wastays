FactoryBot.define do
  factory :room_type do
    association :hotel
    sequence(:name) { |n| "Deluxe #{n}" }
    description { "Spacious room with city view." }
    max_adults { 1 }
    max_children { 1 }
    quantity { 1 }
    base_price { 99.99 }
    room_number_mode { "range" }
  end
end
