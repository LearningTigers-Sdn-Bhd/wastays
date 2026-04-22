FactoryBot.define do
  factory :inventory_audit_log do
    association :hotel
    association :room_type
    association :user
    action_type { "rate_update" }
    old_value { { "date" => Date.current.to_s, "currency" => "MYR", "price" => 120.0 } }
    new_value { { "date" => Date.current.to_s, "currency" => "MYR", "price" => 140.0 } }
    metadata { {} }
  end
end
