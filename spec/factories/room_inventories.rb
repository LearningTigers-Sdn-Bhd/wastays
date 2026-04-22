FactoryBot.define do
  factory :room_inventory do
    association :room_type
    date { Date.current }
    quantity { 1 }
    status { "open" }
  end
end
