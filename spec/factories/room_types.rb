FactoryBot.define do
  factory :room_type do
    hotel { nil }
    name { "MyString" }
    description { "MyText" }
    max_adults { 1 }
    max_children { 1 }
    quantity { 1 }
    base_price { "9.99" }
  end
end
