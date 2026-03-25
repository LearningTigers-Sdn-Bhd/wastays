FactoryBot.define do
  factory :room_inventory do
    room_type { nil }
    date { "2026-03-25" }
    quantity { 1 }
    status { "MyString" }
  end
end
