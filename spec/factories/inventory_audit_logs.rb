FactoryBot.define do
  factory :inventory_audit_log do
    hotel { nil }
    room_type { nil }
    user { nil }
    action_type { "MyString" }
    old_value { "" }
    new_value { "" }
    metadata { "" }
  end
end
