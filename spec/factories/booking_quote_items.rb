FactoryBot.define do
  factory :booking_quote_item do
    association :booking_quote
    association :room_type
    quantity { 1 }
    subtotal { 200.0 }
    room_type_snapshot { { "name" => room_type.name, "max_adults" => room_type.max_adults } }
    nightly_rate_snapshot { { Date.current.to_s => 200.0 } }
    occupancy_snapshot { { "adults" => 2, "children" => 0 } }
  end
end
