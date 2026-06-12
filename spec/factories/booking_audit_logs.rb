FactoryBot.define do
  factory :booking_audit_log do
    association :hotel
    association :auditable, factory: :booking
    association :user
    action_type { "update" }
    category { "stay" }
    source { "staff" }
    occurred_at { Time.current }
    old_value { { "status" => "pending" } }
    new_value { { "status" => "confirmed" } }
    metadata { {} }
  end
end
