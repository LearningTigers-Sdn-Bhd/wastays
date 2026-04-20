FactoryBot.define do
  factory :booking_room do
    association :booking
    association :room_type
    quantity { 1 }
    subtotal { 200.0 }
    room_type_snapshot { {} }
    nightly_rate_snapshot { {} }
    occupancy_snapshot { {} }
  end
end
